package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"strings"
	"time"

	"github.com/apache/pulsar-client-go/pulsar"
	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/mem"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/exporters/stdout/stdoutmetric"
	"go.opentelemetry.io/otel/exporters/stdout/stdouttrace"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

const (
	serviceName    = "pulsar-otel-example"
	serviceVersion = "0.1.0"
)

var (
	logger *zap.Logger
	tracer trace.Tracer

	// Metric instruments
	messagesPublished       metric.Int64Counter
	messagesConsumed        metric.Int64Counter
	messagePublishLatency   metric.Float64Histogram
	messageConsumeLatency   metric.Float64Histogram
	activePulsarConnections metric.Int64UpDownCounter

	// System metrics for Elastic APM
	systemCPUUsage    metric.Float64Gauge
	systemMemoryUsage metric.Float64Gauge
	systemMemoryTotal metric.Float64Gauge
)

func main() {
	// Initialize logger
	var err error
	logger, err = initLogger()
	if err != nil {
		log.Fatalf("Failed to initialize logger: %v", err)
	}
	defer logger.Sync()

	// Initialize tracer
	tp, err := initTracer()
	if err != nil {
		logger.Fatal("Failed to initialize tracer", zap.Error(err))
	}
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := tp.Shutdown(ctx); err != nil {
			logger.Error("Error shutting down tracer provider", zap.Error(err))
		}
	}()

	// Initialize metrics
	mp, err := initMeter()
	if err != nil {
		logger.Fatal("Failed to initialize meter provider", zap.Error(err))
	}
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := mp.Shutdown(ctx); err != nil {
			logger.Error("Error shutting down meter provider", zap.Error(err))
		}
	}()

	// Create Pulsar client
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Start system metrics collection
	go collectSystemMetrics(ctx)

	// Get Pulsar configuration from environment or use defaults
	pulsarURL := getEnvOrDefault("PULSAR_URL", "pulsar://localhost:6650")
	authToken := os.Getenv("PULSAR_AUTH_TOKEN")

	// Create Pulsar client options
	clientOptions := pulsar.ClientOptions{
		URL:               pulsarURL,
		OperationTimeout:  30 * time.Second,
		ConnectionTimeout: 30 * time.Second,
	}

	// Add token authentication if provided
	if authToken != "" {
		clientOptions.Authentication = pulsar.NewAuthenticationToken(authToken)
		logger.Info("Using token authentication")
	} else {
		logger.Info("No authentication token provided, using anonymous access")
	}

	// Create client with options
	client, err := pulsar.NewClient(clientOptions)
	if err != nil {
		logger.Fatal("Failed to create Pulsar client", zap.Error(err))
	}
	defer client.Close()

	// Record connection metric
	recordConnectionChange(ctx, 1, pulsarURL)
	defer recordConnectionChange(ctx, -1, pulsarURL)

	// Create a Pulsar producer with tracing
	producer, err := createTracedProducer(ctx, client)
	if err != nil {
		logger.Fatal("Failed to create producer", zap.Error(err))
	}
	defer producer.Close()

	// Create a Pulsar consumer with tracing
	consumer, err := createTracedConsumer(ctx, client)
	if err != nil {
		logger.Fatal("Failed to create consumer", zap.Error(err))
	}
	defer consumer.Close()

	// Set up signal handling for graceful shutdown
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt)

	// Start a goroutine for producing messages
	go produceMessages(ctx, producer)

	// Start a goroutine for consuming messages
	go consumeMessages(ctx, consumer)

	// Wait for interrupt signal
	<-sigCh
	logger.Info("Shutting down...")
}

func initLogger() (*zap.Logger, error) {
	config := zap.NewDevelopmentConfig()
	return config.Build()
}

func initTracer() (*sdktrace.TracerProvider, error) {
	// Create a resource describing the service
	res, err := resource.New(context.Background(),
		resource.WithFromEnv(),
		resource.WithAttributes(
			// These attributes are added if not present in the environment
			semconv.ServiceName(serviceName),
			semconv.ServiceVersion(serviceVersion),
			attribute.String("environment", "development"),
		),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create resource: %w", err)
	}

	// Check if OTLP endpoint is provided via env var
	var exporter sdktrace.SpanExporter
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint != "" {
		// Use OTLP exporter options
		opts := []otlptracegrpc.Option{
			otlptracegrpc.WithEndpoint(endpoint),
		}

		// Check if we need to use secure or insecure connection
		if os.Getenv("OTEL_EXPORTER_OTLP_INSECURE") == "true" {
			opts = append(opts, otlptracegrpc.WithInsecure())
		}

		// Add headers if provided
		headers := os.Getenv("OTEL_EXPORTER_OTLP_HEADERS")
		if headers != "" {
			opts = append(opts, otlptracegrpc.WithHeaders(parseHeaders(headers)))
		}

		// Create the OTLP client and exporter
		client := otlptracegrpc.NewClient(opts...)
		exporter, err = otlptrace.New(context.Background(), client)
		if err != nil {
			return nil, fmt.Errorf("failed to create OTLP trace exporter: %w", err)
		}
		logger.Info("Using OTLP exporter", zap.String("endpoint", endpoint))
	} else {
		// Fall back to stdout exporter
		exporter, err = stdouttrace.New(stdouttrace.WithPrettyPrint())
		if err != nil {
			return nil, fmt.Errorf("failed to create stdout exporter: %w", err)
		}
		logger.Info("Using stdout exporter")
	}

	// Create trace provider with the exporter
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter,
			// Set a shorter batch timeout to see spans more quickly
			sdktrace.WithBatchTimeout(5*time.Second),
			sdktrace.WithMaxExportBatchSize(10),
		),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
	)

	// Set the global trace provider and propagator
	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	tracer = tp.Tracer(serviceName)
	return tp, nil
}

// initMeter initializes the OpenTelemetry meter provider and instruments
func initMeter() (*sdkmetric.MeterProvider, error) {
	// Create a resource describing the service
	res, err := resource.New(context.Background(),
		resource.WithFromEnv(),
		resource.WithAttributes(
			// These attributes are added if not present in the environment
			semconv.ServiceName(serviceName),
			semconv.ServiceVersion(serviceVersion),
			attribute.String("environment", "development"),
		),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create resource: %w", err)
	}

	// Check if OTLP endpoint is provided via env var
	var reader sdkmetric.Reader
	endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if endpoint != "" {
		// Use OTLP exporter
		opts := []otlpmetricgrpc.Option{
			otlpmetricgrpc.WithEndpoint(endpoint),
		}

		// Check if we need to use secure or insecure connection
		if os.Getenv("OTEL_EXPORTER_OTLP_INSECURE") == "true" {
			opts = append(opts, otlpmetricgrpc.WithInsecure())
		}

		// Add headers if provided
		headers := os.Getenv("OTEL_EXPORTER_OTLP_HEADERS")
		if headers != "" {
			opts = append(opts, otlpmetricgrpc.WithHeaders(parseHeaders(headers)))
		}

		// Create the exporter
		exporter, err := otlpmetricgrpc.New(context.Background(), opts...)
		if err != nil {
			return nil, fmt.Errorf("failed to create OTLP metric exporter: %w", err)
		}

		// Set a specific interval for the periodic reader to ensure metrics are pushed regularly
		// 15 seconds matches our collection interval
		reader = sdkmetric.NewPeriodicReader(exporter,
			sdkmetric.WithInterval(15*time.Second),
			sdkmetric.WithTimeout(10*time.Second),
		)
		logger.Info("Using OTLP metrics exporter",
			zap.String("endpoint", endpoint),
			zap.Duration("push_interval", 15*time.Second),
		)
	} else {
		// Fall back to stdout exporter
		exporter, err := stdoutmetric.New()
		if err != nil {
			return nil, fmt.Errorf("failed to create stdout metric exporter: %w", err)
		}
		reader = sdkmetric.NewPeriodicReader(exporter,
			sdkmetric.WithInterval(15*time.Second),
			sdkmetric.WithTimeout(10*time.Second),
		)
		logger.Info("Using stdout metrics exporter", zap.Duration("push_interval", 15*time.Second))
	}

	// Create a new meter provider with the exporter
	mp := sdkmetric.NewMeterProvider(
		sdkmetric.WithReader(reader),
		sdkmetric.WithResource(res),
		// Add view to ensure no aggregation issues
		sdkmetric.WithView(sdkmetric.NewView(
			sdkmetric.Instrument{Kind: sdkmetric.InstrumentKindUpDownCounter},
			sdkmetric.Stream{Aggregation: sdkmetric.AggregationSum{}},
		)),
	)

	// Set the global meter provider
	otel.SetMeterProvider(mp)

	// Register the meter
	meter := mp.Meter(serviceName)

	// Create instruments
	var err1, err2, err3, err4, err5 error
	messagesPublished, err1 = meter.Int64Counter(
		"pulsar.messages.published",
		metric.WithDescription("Total number of messages published"),
		metric.WithUnit("{messages}"),
	)

	messagesConsumed, err2 = meter.Int64Counter(
		"pulsar.messages.consumed",
		metric.WithDescription("Total number of messages consumed"),
		metric.WithUnit("{messages}"),
	)

	messagePublishLatency, err3 = meter.Float64Histogram(
		"pulsar.message.publish.latency",
		metric.WithDescription("Latency of publishing messages"),
		metric.WithUnit("ms"),
	)

	messageConsumeLatency, err4 = meter.Float64Histogram(
		"pulsar.message.consume.latency",
		metric.WithDescription("Latency of consuming messages"),
		metric.WithUnit("ms"),
	)

	activePulsarConnections, err5 = meter.Int64UpDownCounter(
		"pulsar.connections.active",
		metric.WithDescription("Number of active connections to Pulsar"),
		metric.WithUnit("{connections}"),
	)

	// Create system metrics for Elastic APM
	var errCPU, errMemUsage, errMemTotal error

	// CPU usage metric - using the system.cpu.usage name for Elastic APM compatibility
	systemCPUUsage, errCPU = meter.Float64Gauge(
		"system.cpu.usage",
		metric.WithDescription("CPU usage percentage"),
		metric.WithUnit("1"), // 1 means a ratio/percentage in OpenTelemetry
	)

	// Memory usage metrics - using names compatible with Elastic APM
	systemMemoryUsage, errMemUsage = meter.Float64Gauge(
		"system.memory.usage",
		metric.WithDescription("Memory usage in bytes"),
		metric.WithUnit("By"), // Bytes unit
	)

	systemMemoryTotal, errMemTotal = meter.Float64Gauge(
		"system.memory.total",
		metric.WithDescription("Total system memory in bytes"),
		metric.WithUnit("By"), // Bytes unit
	)

	// Check for errors in creating instruments
	for _, err := range []error{err1, err2, err3, err4, err5, errCPU, errMemUsage, errMemTotal} {
		if err != nil {
			return nil, fmt.Errorf("failed to create instrument: %w", err)
		}
	}

	return mp, nil
}

// Function to record metrics when publishing a message
func recordPublishMetrics(ctx context.Context, duration time.Duration, topic string, success bool) {
	// Record message published count with attributes properly wrapped
	messagesPublished.Add(ctx, 1,
		metric.WithAttributes(
			attribute.String("topic", topic),
			attribute.Bool("success", success),
		),
	)

	// Record publish latency with attributes properly wrapped
	messagePublishLatency.Record(ctx, float64(duration.Milliseconds()),
		metric.WithAttributes(
			attribute.String("topic", topic),
			attribute.Bool("success", success),
		),
	)
}

// Function to record metrics when consuming a message
func recordConsumeMetrics(ctx context.Context, duration time.Duration, topic string, subscription string) {
	// Record message consumed count with attributes properly wrapped
	messagesConsumed.Add(ctx, 1,
		metric.WithAttributes(
			attribute.String("topic", topic),
			attribute.String("subscription", subscription),
		),
	)

	// Record consume processing latency with attributes properly wrapped
	messageConsumeLatency.Record(ctx, float64(duration.Milliseconds()),
		metric.WithAttributes(
			attribute.String("topic", topic),
			attribute.String("subscription", subscription),
		),
	)
}

// Function to track connection state changes
func recordConnectionChange(ctx context.Context, deltaConnections int64, host string) {
	// Record connection change with attributes properly wrapped
	activePulsarConnections.Add(ctx, deltaConnections,
		metric.WithAttributes(
			attribute.String("host", host),
		),
	)
}

// Function to collect system metrics periodically
func collectSystemMetrics(ctx context.Context) {
	ticker := time.NewTicker(15 * time.Second)
	defer ticker.Stop()

	hostAttributes := []attribute.KeyValue{
		attribute.String("host.name", getHostname()),
	}

	logger.Info("Starting system metrics collection", zap.Duration("interval", 15*time.Second))

	// Collect metrics immediately on startup, then on ticker
	collectAndRecordMetrics(ctx, hostAttributes)

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			collectAndRecordMetrics(ctx, hostAttributes)
		}
	}
}

// Helper function to collect and record metrics
func collectAndRecordMetrics(ctx context.Context, hostAttributes []attribute.KeyValue) {
	// Collect CPU usage
	cpuPercent, err := cpu.Percent(0, false)
	if err == nil && len(cpuPercent) > 0 {
		// Convert to ratio (0.0-1.0) as per OpenTelemetry conventions
		cpuRatio := cpuPercent[0] / 100.0
		systemCPUUsage.Record(ctx, cpuRatio, metric.WithAttributes(hostAttributes...))
		logger.Info("Recorded CPU usage", zap.Float64("usage_ratio", cpuRatio))
	} else if err != nil {
		logger.Error("Failed to collect CPU metrics", zap.Error(err))
	}

	// Collect memory usage
	memInfo, err := mem.VirtualMemory()
	if err == nil {
		// Record memory usage in bytes
		systemMemoryUsage.Record(ctx, float64(memInfo.Used), metric.WithAttributes(hostAttributes...))
		systemMemoryTotal.Record(ctx, float64(memInfo.Total), metric.WithAttributes(hostAttributes...))
		logger.Info("Recorded memory metrics",
			zap.Uint64("used_bytes", memInfo.Used),
			zap.Uint64("total_bytes", memInfo.Total),
		)
	} else {
		logger.Error("Failed to collect memory metrics", zap.Error(err))
	}
}

// Get hostname for metric attributes
func getHostname() string {
	hostname, err := os.Hostname()
	if err != nil {
		return "unknown"
	}
	return hostname
}

// Helper function to parse OTLP headers from string in format "key1=value1,key2=value2"
func parseHeaders(headerString string) map[string]string {
	headers := make(map[string]string)
	// Simple parsing - in production you might want more robust parsing
	for _, pair := range strings.Split(headerString, ",") {
		parts := strings.SplitN(pair, "=", 2)
		if len(parts) == 2 {
			headers[parts[0]] = parts[1]
		}
	}
	return headers
}

// Helper function to get environment variable or default value
func getEnvOrDefault(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func createTracedProducer(ctx context.Context, client pulsar.Client) (pulsar.Producer, error) {
	topic := getEnvOrDefault("PULSAR_TOPIC", "my-topic")
	producerName := getEnvOrDefault("PULSAR_PRODUCER_NAME", "my-producer")

	// Use messaging semantic conventions
	ctx, span := tracer.Start(ctx, fmt.Sprintf("%s create_producer", topic),
		trace.WithAttributes(
			semconv.MessagingSystem("pulsar"),
			semconv.MessagingDestinationName(topic),
			attribute.String("pulsar.producer", producerName),
		),
	)
	defer span.End()

	logger.Info("Creating Pulsar producer",
		zap.String("topic", topic),
		zap.String("producer", producerName),
		zap.String("trace_id", span.SpanContext().TraceID().String()),
		zap.String("span_id", span.SpanContext().SpanID().String()))

	producer, err := client.CreateProducer(pulsar.ProducerOptions{
		Topic: topic,
		Name:  producerName,
	})
	if err != nil {
		span.RecordError(err)
		return nil, err
	}

	return producer, nil
}

func createTracedConsumer(ctx context.Context, client pulsar.Client) (pulsar.Consumer, error) {
	topic := getEnvOrDefault("PULSAR_TOPIC", "my-topic")
	subscription := getEnvOrDefault("PULSAR_SUBSCRIPTION", "my-subscription")

	// Use messaging semantic conventions
	ctx, span := tracer.Start(ctx, fmt.Sprintf("%s create_consumer", topic),
		trace.WithAttributes(
			semconv.MessagingSystem("pulsar"),
			semconv.MessagingDestinationName(topic),
			attribute.String("pulsar.subscription", subscription),
		),
	)
	defer span.End()

	logger.Info("Creating Pulsar consumer",
		zap.String("topic", topic),
		zap.String("subscription", subscription),
		zap.String("trace_id", span.SpanContext().TraceID().String()),
		zap.String("span_id", span.SpanContext().SpanID().String()))

	consumer, err := client.Subscribe(pulsar.ConsumerOptions{
		Topic:            topic,
		SubscriptionName: subscription,
		Type:             pulsar.Shared,
	})
	if err != nil {
		span.RecordError(err)
		return nil, err
	}

	return consumer, nil
}

// InjectTraceContext injects the trace context into the message properties
func injectTraceContext(ctx context.Context, properties map[string]string) map[string]string {
	if properties == nil {
		properties = make(map[string]string)
	}
	// Use the OpenTelemetry propagator to inject trace context
	otel.GetTextMapPropagator().Inject(ctx, propagationMapCarrier(properties))

	return properties
}

// ExtractTraceContext extracts the trace context from message properties
// and returns a new context with the extracted span context
func extractTraceContext(ctx context.Context, properties map[string]string) context.Context {
	return otel.GetTextMapPropagator().Extract(ctx, propagationMapCarrier(properties))
}

// propagationMapCarrier adapts a string map to the TextMapCarrier interface
type propagationMapCarrier map[string]string

func (c propagationMapCarrier) Get(key string) string {
	return c[key]
}

func (c propagationMapCarrier) Set(key string, value string) {
	c[key] = value
}

func (c propagationMapCarrier) Keys() []string {
	keys := make([]string, 0, len(c))
	for k := range c {
		keys = append(keys, k)
	}
	return keys
}

func produceMessages(ctx context.Context, producer pulsar.Producer) {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	msgCount := 0
	topic := producer.Topic()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			startTime := time.Now()

			msgCount++
			msgId := fmt.Sprintf("msg-%d", msgCount)
			message := fmt.Sprintf("Hello, OpenTelemetry! Message %d", msgCount)

			// Create span with proper name and attributes
			msgCtx, span := tracer.Start(ctx, fmt.Sprintf("%s publish", topic),
				trace.WithAttributes(
					semconv.MessagingSystem("pulsar"),
					semconv.MessagingOperationPublish,
					semconv.MessagingMessageID(msgId),
					semconv.MessagingDestinationName(topic),
				),
			)

			// Base message properties
			properties := map[string]string{
				"message_id": msgId,
			}

			// Ensure trace context is properly injected
			properties = injectTraceContext(msgCtx, properties)

			logger.Info("Producing message",
				zap.String("message_id", msgId),
				zap.String("content", message),
				zap.String("topic", topic),
				zap.String("trace_id", span.SpanContext().TraceID().String()),
				zap.String("span_id", span.SpanContext().SpanID().String()))

			// Send message with trace context
			msgID, err := producer.Send(msgCtx, &pulsar.ProducerMessage{
				Payload:    []byte(message),
				Properties: properties,
			})

			// Record metrics
			duration := time.Since(startTime)
			success := err == nil
			recordPublishMetrics(ctx, duration, topic, success)

			if err != nil {
				logger.Error("Failed to publish message", zap.Error(err))
				span.RecordError(err)
				span.SetStatus(codes.Error, "Failed to publish message")
			} else {
				logger.Info("Published message",
					zap.String("messageID", msgID.String()),
					zap.String("trace_id", span.SpanContext().TraceID().String()),
					zap.String("span_id", span.SpanContext().SpanID().String()))
				span.SetAttributes(attribute.String("pulsar.message_id", msgID.String()))
			}

			span.End()
		}
	}
}

func consumeMessages(ctx context.Context, consumer pulsar.Consumer) {
	// Get topic and subscription from environment variables directly
	topic := getEnvOrDefault("PULSAR_TOPIC", "my-topic")
	subscription := getEnvOrDefault("PULSAR_SUBSCRIPTION", "my-subscription")

	logger.Info("Starting consumer",
		zap.String("topic", topic),
		zap.String("subscription", subscription))

	for {
		select {
		case <-ctx.Done():
			return
		default:
			startTime := time.Now()
			msg, err := consumer.Receive(ctx)
			if err != nil {
				logger.Error("Error receiving message", zap.Error(err))
				continue
			}

			properties := msg.Properties()
			msgID := "unknown"
			if id, ok := properties["message_id"]; ok {
				msgID = id
			}

			// Extract trace context from message properties
			msgCtx := extractTraceContext(ctx, properties)

			// Create process span with proper name and attributes
			msgCtx, span := tracer.Start(msgCtx, fmt.Sprintf("%s process", topic),
				trace.WithAttributes(
					semconv.MessagingSystem("pulsar"),
					semconv.MessagingOperationProcess,
					semconv.MessagingMessageID(msgID),
					semconv.MessagingDestinationName(topic),
					attribute.String("pulsar.subscription", subscription),
					attribute.String("pulsar.message_id", msg.ID().String()),
				),
			)

			// Process the message
			data := string(msg.Payload())
			logger.Info("Received message",
				zap.String("messageID", msg.ID().String()),
				zap.String("content", data),
				zap.String("topic", topic),
				zap.String("trace_id", span.SpanContext().TraceID().String()),
				zap.String("span_id", span.SpanContext().SpanID().String()))

			// Acknowledge the message
			consumer.Ack(msg)

			// Record metrics
			duration := time.Since(startTime)
			recordConsumeMetrics(ctx, duration, topic, subscription)

			span.AddEvent("message acknowledged")
			span.End()

			// Simulate processing time
			time.Sleep(500 * time.Millisecond)
		}
	}
}
