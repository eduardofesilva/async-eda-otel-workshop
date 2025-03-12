# Create namespace for KAAP
resource "kubernetes_namespace" "kaap" {
  metadata {
    name = "kaap-system"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Create secrets required for KAAP
resource "kubernetes_secret" "pulsar_admin_console_user" {
  metadata {
    name      = "pulsar-admin-console-user"
    namespace = kubernetes_namespace.kaap.metadata[0].name
  }

  data = {
    username = var.secretConfig.pulsar_admin_console_username
    password = var.secretConfig.pulsar_admin_console_password
  }

  type = "Opaque"
}

# Create a self-signed issuer for our certificates
resource "kubectl_manifest" "self_signed_issuer" {
  yaml_body = <<-YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
  YAML
  depends_on = [
    time_sleep.wait_for_cert_manager_crds
  ]
}

# Create the Pulsar TLS certificate
resource "kubectl_manifest" "pulsar_certificate" {
  yaml_body = <<-YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: pulsar-tls
  namespace: kaap-system
spec:
  secretName: pulsar-tls
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
  dnsNames:
  - "${var.route53_config.pulsar_subdomain}.${var.route53_config.domain_name}"
  - "*.${var.route53_config.pulsar_subdomain}.${var.route53_config.domain_name}"
  duration: 2160h # 90 days
  renewBefore: 360h # 15 days
  privateKey:
    algorithm: RSA
    encoding: PKCS1
    size: 2048
  YAML

  depends_on = [
    kubectl_manifest.self_signed_issuer,
    kubernetes_namespace.kaap
  ]
}

# Wait for certificate to be issued
resource "time_sleep" "wait_for_certificate" {
  depends_on = [kubectl_manifest.pulsar_certificate]
  create_duration = "30s"
}

# Install KAAP via Helm
resource "helm_release" "kaap" {
  name       = "kaap"
  repository = "https://datastax.github.io/kaap"
  chart      = "kaap"
  namespace  = kubernetes_namespace.kaap.metadata[0].name
  
  # Production settings
  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 600

  values = [
    <<-EOT
    kaap:
      operator:
        config:
          quarkus: {}
      cluster:
        create: false
    pulsar-admin-console:
      enabled: true
      env:
        - name: NODE_EXTRA_CA_CERTS
          value: /pulsar/certs/ca.crt
      additionalVolumes:
        - name: certs
          secret:
            secretName: pulsar-tls
        - name: token-superuser
          secret:
            secretName: token-superuser
        - name: token-private-key
          secret:
            secretName: token-private-key
      additionalVolumeMounts:
        - name: certs
          readOnly: true
          mountPath: /pulsar/certs
        - name: token-superuser
          readOnly: true
          mountPath: /pulsar/token-superuser
        - name: token-private-key
          readOnly: true
          mountPath: /pulsar/token-private-key
      createUserSecret:
        enabled: true
        user: ${var.secretConfig.pulsar_admin_console_username}
        password: ${var.secretConfig.pulsar_admin_console_password}
      config:
        auth_mode: k8s
        grafana_url: http://pulsar-grafana:3000
        host_overrides:
          pulsar: pulsar://pulsar-broker:6650
          http: http://pulsar-broker:8080
        server_config:
          pulsar_url: http://pulsar-broker:8080
          function_worker_url: https://pulsar-function:6751
    # Use external cert-manager that we've already installed
    cert-manager:
      enabled: false
    EOT
  ]

  depends_on = [
    kubernetes_namespace.kaap,
    kubernetes_secret.pulsar_admin_console_user,
    helm_release.aws_load_balancer_controller,
    time_sleep.wait_for_certificate
  ]
}

# Wait for KAAP CRDs to be registered
resource "time_sleep" "wait_for_kaap_crd" {
  depends_on = [helm_release.kaap]
  create_duration = "30s"
}

# Create the PulsarCluster resource explicitly
resource "kubectl_manifest" "pulsar_cluster" {
  yaml_body = <<-YAML
apiVersion: kaap.oss.datastax.com/v1beta1
kind: PulsarCluster
metadata:
  name: pulsar
  namespace: kaap-system
spec:
  global:
    name: pulsar
    image: ${var.kaapConfig.pulsar_image_tag}
    restartOnConfigMapChange: true
    storage:
      existingStorageClassName: gp3
    auth:
      enabled: true
      token:
        initialize: true
        superUserRoles: ["admin", "proxy", "superuser", "websocket"]
    antiAffinity:
      host:
        enabled: false
        required: false
    tls:
      enabled: false
      zookeeper:
        enabled: false
      bookkeeper:
        enabled: false
      autorecovery:
        enabled: false
      proxy:
        enabled: false
      broker:
        enabled: false
      certProvisioner:
        selfSigned:
          enabled: false
        certManager:
          enabled: false
  zookeeper:
    replicas: ${var.kaapConfig.zookeeper_count}
    dataVolume:
      name: data
      size: 100M
    resources:
      requests:
        cpu: "0.2"
        memory: "128Mi"
  bookkeeper:
    replicas: ${var.kaapConfig.bookkeeper_count}
    volumes:
      journal:
        size: 1Gi
      ledgers:
        size: 1Gi
    resources:
      requests:
        cpu: "0.2"
        memory: 128Mi
  broker:
    replicas: ${var.kaapConfig.broker_count}
    env:
      - name: PULSAR_LOG_LEVEL
        value: ${var.kaapConfig.log_level}
      - name: PULSAR_LOG_ROOT_LEVEL
        value: ${var.kaapConfig.log_level}
    config:
      managedLedgerDefaultAckQuorum: "2"
      managedLedgerDefaultEnsembleSize: "2"
      managedLedgerDefaultWriteQuorum: "2"
      topicLevelPoliciesEnabled: "true"
      allowAutoTopicCreation: "false"
      systemTopicEnabled: "true"
      brokerDeleteInactiveTopicsEnabled: "false"
      allowAutoSubscriptionCreation: "false"
      authenticationProviders: "org.apache.pulsar.broker.authentication.AuthenticationProviderToken"
    resources:
      requests:
        cpu: "0.2"
        memory: 128Mi
  proxy:
    replicas: ${var.kaapConfig.proxy_count}
    service:
      annotations:
        service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
        service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
        external-dns.alpha.kubernetes.io/hostname: "${var.route53_config.pulsar_subdomain}.${var.route53_config.domain_name}"
        service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
        service.beta.kubernetes.io/aws-load-balancer-security-groups: "${aws_security_group.pulsar_security_group.id}"
        ${var.kaapConfig.internal_lb ? "service.beta.kubernetes.io/aws-load-balancer-internal: \"true\"" : ""}
      type: LoadBalancer
      externalIPs: []
    config:
      webServicePort: 8080  # HTTP port
      webServicePortTls: ""  # Disable HTTPS port
      tlsEnabledInProxy: "false"
      
      # Remove all TLS-related settings
      tlsKeyStore: ""
      tlsKeyStorePassword: ""
      tlsTrustStore: ""
      tlsTrustStorePassword: ""
      tlsCertificateFilePath: ""
      tlsKeyFilePath: ""
      tlsTrustCertsFilePath: ""
      
      # Other existing config values
      managedLedgerDefaultAckQuorum: "2"
      managedLedgerDefaultEnsembleSize: "2"
      managedLedgerDefaultWriteQuorum: "2"
      topicLevelPoliciesEnabled: "true"
      allowAutoTopicCreation: "false"
      systemTopicEnabled: "true"
      brokerDeleteInactiveTopicsEnabled: "false"
      allowAutoSubscriptionCreation: "false"
      authenticationProviders: "org.apache.pulsar.broker.authentication.AuthenticationProviderToken"
    resources:
      requests:
        cpu: "0.2"
        memory: 128Mi
    # Remove all TLS-related volumes and init containers
  autorecovery:
    replicas: 1
    resources:
      requests:
        cpu: "0.2"
        memory: 128Mi
  bastion:
    replicas: 1
    resources:
      requests:
        cpu: "0.2"
        memory: 128Mi
  YAML

  depends_on = [
    helm_release.kaap,
    time_sleep.wait_for_kaap_crd,
    aws_security_group.pulsar_security_group
  ]
}