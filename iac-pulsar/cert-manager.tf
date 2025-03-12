# Create namespace for cert-manager
resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = var.cert_manager_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Create IAM policy for Route53 DNS validation
resource "aws_iam_policy" "cert_manager_route53" {
  name        = "${var.cluster_name}-cert-manager-route53"
  description = "Policy allowing cert-manager to use Route53 for DNS01 challenges"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:GetChange",
          "route53:ListHostedZonesByName"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/${var.route53_config.hosted_zone_id}"
      }
    ]
  })
}

# Update the assume role policy for the cert-manager IAM role
resource "aws_iam_role" "cert_manager_route53" {
  name = "${var.cluster_name}-cert-manager-route53"
  
  # Update the trust relationship to trust the EKS OIDC provider directly
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:cert-manager:cert-manager"
          }
        }
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "cert_manager_route53" {
  role       = aws_iam_role.cert_manager_route53.name
  policy_arn = aws_iam_policy.cert_manager_route53.arn
}

# Update the service account for cert-manager
resource "kubernetes_service_account" "cert_manager_route53" {
  metadata {
    name      = "cert-manager"
    namespace = "cert-manager"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cert_manager_route53.arn
    }
  }

  depends_on = [
    kubernetes_namespace.cert_manager
  ]
}

# Install cert-manager via Helm
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  version    = var.cert_manager_chart_version

  # Production settings
  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 300

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.cert_manager_route53.metadata[0].name
  }

  # Configure resources if set
  dynamic "set" {
    for_each = var.cert_manager_set_resources ? [1] : []
    content {
      name  = "resources.requests.cpu"
      value = var.cert_manager_cpu_request
    }
  }

  dynamic "set" {
    for_each = var.cert_manager_set_resources ? [1] : []
    content {
      name  = "resources.requests.memory"
      value = var.cert_manager_memory_request
    }
  }

  dynamic "set" {
    for_each = var.cert_manager_set_resources ? [1] : []
    content {
      name  = "resources.limits.cpu"
      value = var.cert_manager_cpu_limit
    }
  }

  dynamic "set" {
    for_each = var.cert_manager_set_resources ? [1] : []
    content {
      name  = "resources.limits.memory"
      value = var.cert_manager_memory_limit
    }
  }

  set {
    name  = "replicaCount"
    value = var.cert_manager_replicas
  }

  # Wait for AWS Load Balancer Controller to be installed first
  depends_on = [
    kubernetes_namespace.cert_manager,
    kubernetes_service_account.cert_manager_route53,
    aws_iam_role_policy_attachment.cert_manager_route53
  ]
}

# Wait for cert-manager to be fully deployed and CRDs registered
resource "time_sleep" "wait_for_cert_manager" {
  depends_on = [helm_release.cert_manager]
  create_duration = "30s"
}
# Update the ClusterIssuer for Let's Encrypt
resource "kubectl_manifest" "letsencrypt_issuer" {
  yaml_body = <<-YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${var.route53_config.email}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - selector:
        dnsZones:
          - "${var.route53_config.domain_name}"
      dns01:
        route53:
          region: ${var.route53_config.region}
          hostedZoneID: ${var.route53_config.hosted_zone_id}
          # Remove the role reference - we'll use the annotated service account instead
  YAML

  depends_on = [
    time_sleep.wait_for_cert_manager
  ]
}

# Add or update this resource to wait for cert-manager CRDs to be registered
resource "time_sleep" "wait_for_cert_manager_crds" {
  depends_on = [helm_release.cert_manager]
  create_duration = "60s"  # Increased time to ensure CRDs are fully registered
}

# Add additional wait to ensure cert-manager is fully operational
resource "time_sleep" "wait_for_cert_manager_all" {
  depends_on = [
    time_sleep.wait_for_cert_manager,
    time_sleep.wait_for_cert_manager_crds
  ]
  create_duration = "10s"
}

# Create a local-exec to check for cert-manager CRDs
resource "null_resource" "verify_cert_manager_crds" {
  depends_on = [time_sleep.wait_for_cert_manager]
  
  provisioner "local-exec" {
    command = "kubectl get crd | grep cert-manager.io || echo 'CRDs not found!'"
  }
}