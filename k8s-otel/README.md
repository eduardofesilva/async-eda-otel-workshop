# OpenTelemetry Installation

## How to

1. Check [here](https://opentelemetry.io/docs/platforms/kubernetes/helm/operator/#installing-the-chart) for further details on the installation 
```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm install my-opentelemetry-operator open-telemetry/opentelemetry-operator \
  --set "manager.collectorImage.repository=otel/opentelemetry-collector-k8s" \
  --set admissionWebhooks.certManager.enabled=false \
  --set admissionWebhooks.autoGenerateCert.enabled=true
```

2. Apply the OpenTelemetry Collector Custom Resource Definition (CRD):
```bash
kubectl apply -f ./otel-crd.yml
```

## Expected Outputs

After deploying the OpenTelemetry Operator and Collector, you should see the following:

### OpenTelemetry Operator Deployment
```bash
kubectl get pods -n otel
```
Output:
```
NAME                                  READY   STATUS    RESTARTS   AGE
my-opentelemetry-operator-xxxxxx      1/1     Running   0          1m
```

### OpenTelemetry Collector Deployment
```bash
kubectl get pods -n otel
```
Output:
```
NAME                                  READY   STATUS    RESTARTS   AGE
otel-collector-xxxxxx                 1/1     Running   0          1m
```

### OpenTelemetry Collector Configuration
The configuration for the OpenTelemetry Collector is defined in the `otel-crd.yml` file. Here is a summary of the configuration:

- **Receivers**:
  - `otlp`: Receives data over gRPC and HTTP on ports 4317 and 4318.
  - `jaeger`: Receives data over HTTP and gRPC on ports 14268 and 14250.
  - `zipkin`: Receives data on port 9411.

- **Processors**:
  - `batch`: Batches data before sending it to exporters.
  - `memory_limiter`: Limits memory usage.

- **Exporters**:
  - `otlp`: Exports data to Jaeger and Grafana Tempo.
  - `debug`: Outputs detailed logs for debugging.

- **Service Pipelines**:
  - `traces`: Receives data from `otlp`, `jaeger`, and `zipkin`, processes it with `memory_limiter` and `batch`, and exports it to `otlp` and `debug`.
  - `logs`: Receives data from `otlp`, processes it with `memory_limiter` and `batch`, and exports it to `otlp` and `debug`.

### Verifying the Deployment
To verify that the OpenTelemetry Collector is receiving and exporting data correctly, you can check the logs of the collector pod:

```bash
kubectl logs -n otel otel-collector-xxxxxx
```

You should see logs indicating that the collector is receiving and exporting data.

## Additional Resources

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [OpenTelemetry Helm Charts](https://github.com/open-telemetry/opentelemetry-helm-charts)
