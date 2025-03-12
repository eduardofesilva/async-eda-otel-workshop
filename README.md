# OpenTelemetry Event-Driven Architecture Project

This project demonstrates an event-driven architecture using Apache Pulsar and OpenTelemetry for observability. The project includes infrastructure deployment using Terraform, Kubernetes configurations, and a Go application that integrates Pulsar with OpenTelemetry.

## Execution Steps

### 1. Deploy EKS Cluster

Navigate to the `iac-eks` directory and deploy the EKS cluster using Terraform.

```bash
cd ./iac-eks
terraform init
terraform plan
terraform apply -auto-approve
```

### 2. Deploy Apache Pulsar on Kubernetes

Navigate to the `iac-pulsar` directory and deploy Apache Pulsar using Terraform.

```bash
cd ./iac-pulsar
terraform init
terraform plan
terraform apply -auto-approve
```

### 3. Install OpenTelemetry Collector

Navigate to the `k8s-otel` directory and install the OpenTelemetry Collector using Helm.

```bash
cd ./k8s-otel
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm install my-opentelemetry-operator open-telemetry/opentelemetry-operator \
  --set "manager.collectorImage.repository=otel/opentelemetry-collector-k8s" \
  --set admissionWebhooks.certManager.enabled=false \
  --set admissionWebhooks.autoGenerateCert.enabled=true
kubectl apply -f ./otel-crd.yml
```

### 4. Run the Pulsar OpenTelemetry App

Navigate to the `app` directory, build, and run the Go application.

```bash
cd ./app
go build -o app
PULSAR_URL=pulsar://localhost:6650 PULSAR_TOPIC=my-topic OTEL_EXPORTER_OTLP_ENDPOINT=localhost:4317 ./app
```

## Overview

This project includes:

- **Infrastructure as Code (IaC)**: Terraform configurations for deploying an EKS cluster and Apache Pulsar.
- **Kubernetes Configurations**: Helm charts and manifests for deploying OpenTelemetry Collector.
- **Go Application**: A demonstration app that integrates Apache Pulsar with OpenTelemetry for tracing and metrics.

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform v1.0.0+ installed
- kubectl installed and configured to access your EKS cluster
- Helm v3 installed
- Go 1.16 or later
- Apache Pulsar cluster (can be run locally)
- OpenTelemetry Collector
- Jaeger, Zipkin, or another compatible tracing backend

## Additional Resources

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [Apache Pulsar Documentation](https://pulsar.apache.org/docs/en/next/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
