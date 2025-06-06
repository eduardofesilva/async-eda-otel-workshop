# Install Istio and configure ingress for Pulsar

resource "kubernetes_namespace" "istio_system" {
  metadata {
    name = var.istio_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "istio_base" {
  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  namespace  = kubernetes_namespace.istio_system.metadata[0].name
  version    = var.istio_version
}

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = kubernetes_namespace.istio_system.metadata[0].name
  version    = var.istio_version
  depends_on = [helm_release.istio_base]
}

resource "helm_release" "istio_ingress" {
  name       = "istio-ingress"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  namespace  = kubernetes_namespace.istio_system.metadata[0].name
  version    = var.istio_version
  depends_on = [helm_release.istiod]
}

resource "kubectl_manifest" "pulsar_gateway" {
  yaml_body = <<-YAML
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: pulsar-gateway
  namespace: kaap-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "${var.route53_config.pulsar_subdomain}.${var.route53_config.domain_name}"
  YAML
  depends_on = [helm_release.istio_ingress]
}

resource "kubectl_manifest" "pulsar_virtual_service" {
  yaml_body = <<-YAML
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: pulsar
  namespace: kaap-system
spec:
  hosts:
  - "${var.route53_config.pulsar_subdomain}.${var.route53_config.domain_name}"
  gateways:
  - kaap-system/pulsar-gateway
  http:
  - match:
    - uri:
        prefix: "/"
    route:
    - destination:
        host: pulsar-proxy
        port:
          number: 8080
  YAML
  depends_on = [kubectl_manifest.pulsar_gateway]
}
