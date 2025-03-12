# Pulsar OpenTelemetry App

A demonstration application that integrates Apache Pulsar with OpenTelemetry for event-driven architecture observability using Go. This application runs both producer and consumer in a single process, demonstrating end-to-end tracing through the messaging system.

## Prerequisites

- Go 1.16 or later
- Apache Pulsar cluster (can be run locally)
- OpenTelemetry Collector
- Jaeger, Zipkin, or another compatible tracing backend

## Required Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PULSAR_URL` | Connection URL for Pulsar broker | `pulsar://localhost:6650` |
| `PULSAR_AUTH_TOKEN` | Authentication token for Pulsar (optional) | |
| `PULSAR_TOPIC` | Pulsar topic to produce/consume messages | `my-topic` |
| `PULSAR_PRODUCER_NAME` | Name of the producer | `my-producer` |
| `PULSAR_SUBSCRIPTION` | Subscription name for the consumer | `my-subscription` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | OpenTelemetry collector endpoint | |
| `OTEL_EXPORTER_OTLP_INSECURE` | Set to "true" for insecure connection | |
| `OTEL_EXPORTER_OTLP_HEADERS` | Headers for OTLP exporter in format "key1=value1,key2=value2" | |

## How to Run

```bash
go build -o app
# Make sure that you exporta the environment variable above
PULSAR_URL=pulsar://localhost:6650 PULSAR_TOPIC=my-topic OTEL_EXPORTER_OTLP_ENDPOINT=localhost:4317 ./app
```

```bash
# Visualizing your traces in the terminal
https://github.com/equinix-labs/otel-cli
otel-cli server tui
```


## Code Overview

This application demonstrates event-driven architecture observability using OpenTelemetry and Apache Pulsar with Go.

### Components

- **Single Process Application**: Contains both producer and consumer logic running concurrently.
- **Producer**: Sends messages every 2 seconds with trace context attached.
- **Consumer**: Processes incoming messages, extracts trace context, and creates child spans.
- **OpenTelemetry Integration**:
  - **Tracing**: Captures spans across the entire message journey with context propagation.
  - **Metrics**: Collects custom metrics (message counts, latencies) and system metrics (CPU, memory).
  - **Exporters**: Configurable to send telemetry to OTLP endpoints or standard output.

### Workflow

1. The application initializes both a producer and consumer connection to Pulsar
2. The producer sends a message every 2 seconds to the configured Pulsar topic
3. Each produced message creates a new trace span and attaches the context to the message
4. The consumer (in the same process) receives the message and extracts the trace context
5. Message processing occurs as a child span of the original trace
6. Both trace data and metrics are exported to the configured OpenTelemetry backend

### Metrics Collected

- `pulsar.messages.published`: Counter for messages published
- `pulsar.messages.consumed`: Counter for messages consumed
- `pulsar.message.publish.latency`: Histogram of message publish latencies
- `pulsar.message.consume.latency`: Histogram of message consume latencies
- `pulsar.connections.active`: Active connections to Pulsar
- System metrics: CPU usage, memory usage, and total memory

This setup enables end-to-end visibility across the message-based communication, allowing you to track the flow of events through the system and identify performance issues or failures.

