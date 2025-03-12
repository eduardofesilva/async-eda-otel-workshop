# Create namespace for external-dns
resource "kubernetes_namespace" "external_dns" {
  metadata {
    name = "external-dns"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Create IAM policy for external-dns with corrected trust relationship
resource "aws_iam_policy" "external_dns" {
  name        = "${var.cluster_name}-external-dns"
  description = "Policy allowing external-dns to update Route53 records"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = [
          "arn:aws:route53:::hostedzone/${var.route53_config.hosted_zone_id}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets"
        ]
        Resource = [
          "*"
        ]
      }
    ]
  })
}

# Create IAM role for external-dns with corrected trust relationship
resource "aws_iam_role" "external_dns" {
  name = "${var.cluster_name}-external-dns"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_provider}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_provider}:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "${local.oidc_provider}:sub" = "system:serviceaccount:external-dns:external-dns"
          }
        }
      }
    ]
  })
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}

# Create ServiceAccount for external-dns with explicit annotation for the role
resource "kubernetes_service_account" "external_dns" {
  metadata {
    name      = "external-dns"
    namespace = kubernetes_namespace.external_dns.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns.arn
    }
  }
}

# Update the external-dns Helm release with correct IAM annotations
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  namespace  = kubernetes_namespace.external_dns.metadata[0].name
  version    = "1.13.1"  # Set an explicit version
  
  # Make sure to wait for resources to be available
  wait      = true
  atomic    = true
  
  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "namespace"
    value = ""  # Empty string means watch all namespaces
  }
  
  set {
    name  = "aws.region"
    value = var.region
  }
  
  set {
    name  = "aws.zoneType"
    value = "public" # Specify that we're working with public zones
  }
  
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.external_dns.metadata[0].name
  }
  
  set {
    name  = "txtOwnerId"
    value = var.cluster_name
  }
  
  set {
    name  = "domainFilters[0]"
    value = var.route53_config.domain_name
  }
  
  set {
    name  = "policy"
    value = "sync" # Creates and updates records but never deletes them
  }
  
  # Explicitly set annotation on the deployment
  set {
    name  = "podAnnotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_dns.arn
  }
  
  depends_on = [
    kubernetes_namespace.external_dns,
    kubernetes_service_account.external_dns,
    aws_iam_role_policy_attachment.external_dns
  ]
}