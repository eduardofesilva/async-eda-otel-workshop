resource "kubernetes_service_account" "aws_ebs_csi_driver" {
  metadata {
    name      = "ebs-csi-controller-sa"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.aws_ebs_csi_driver.arn
    }
    labels = {
      "app.kubernetes.io/name"       = "aws-ebs-csi-driver"
      "app.kubernetes.io/component"  = "controller"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "aws_iam_policy" "aws_ebs_csi_driver" {
  name        = "AmazonEKS_EBS_CSI_Driver_Policy"
  description = "IAM policy for the Amazon EBS CSI Driver"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:AttachVolume",
          "ec2:DetachVolume",
          "ec2:ModifyVolume",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeSnapshots",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ]
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = [
              "CreateVolume",
              "CreateSnapshot"
            ]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteTags"
        ]
        Resource = [
          "arn:aws:ec2:*:*:volume/*",
          "arn:aws:ec2:*:*:snapshot/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:RequestTag/ebs.csi.aws.com/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:RequestTag/CSIVolumeName" = "*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:RequestTag/kubernetes.io/cluster/*" = "owned"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/ebs.csi.aws.com/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/CSIVolumeName" = "*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteVolume"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/kubernetes.io/cluster/*" = "owned"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteSnapshot"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/CSIVolumeSnapshotName" = "*"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DeleteSnapshot"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/ebs.csi.aws.com/cluster" = "true"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role" "aws_ebs_csi_driver" {
  name = "aws-ebs-csi-driver-role"
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
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "aws_ebs_csi_driver" {
  role       = aws_iam_role.aws_ebs_csi_driver.name
  policy_arn = aws_iam_policy.aws_ebs_csi_driver.arn
}

resource "helm_release" "aws_ebs_csi_driver" {
  name       = "aws-ebs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart      = "aws-ebs-csi-driver"
  namespace  = "kube-system"
  version    = var.aws_ebs_csi_driver_chart_version

  set {
    name  = "controller.serviceAccount.create"
    value = "false"
  }

  set {
    name  = "controller.serviceAccount.name"
    value = "ebs-csi-controller-sa"
  }

  set {
    name  = "node.serviceAccount.create"
    value = "false"
  }

  set {
    name  = "node.serviceAccount.name"
    value = "ebs-csi-controller-sa"
  }

  # Enable volume resizing if specified
  set {
    name  = "controller.volumeModificationFeature.enabled"
    value = var.enable_volume_resizing
  }

  # Enable volume snapshot if specified
  set {
    name  = "controller.volumeSnapshotFeature.enabled"
    value = var.enable_volume_snapshot
  }

  # Set controller replica count
  set {
    name  = "controller.replicaCount"
    value = var.ebs_csi_controller_replicas
  }

  # Set resource requests/limits if specified
  dynamic "set" {
    for_each = var.set_controller_resources ? [1] : []
    content {
      name  = "controller.resources.requests.cpu"
      value = var.controller_cpu_request
    }
  }

  dynamic "set" {
    for_each = var.set_controller_resources ? [1] : []
    content {
      name  = "controller.resources.requests.memory"
      value = var.controller_memory_request
    }
  }

  dynamic "set" {
    for_each = var.set_controller_resources ? [1] : []
    content {
      name  = "controller.resources.limits.cpu" 
      value = var.controller_cpu_limit
    }
  }

  dynamic "set" {
    for_each = var.set_controller_resources ? [1] : []
    content {
      name  = "controller.resources.limits.memory"
      value = var.controller_memory_limit
    }
  }

  depends_on = [
    kubernetes_service_account.aws_ebs_csi_driver,
    aws_iam_role_policy_attachment.aws_ebs_csi_driver
  ]
}

# Optional: Create storage class for gp3 volumes
resource "kubernetes_storage_class" "gp3" {
  count = var.create_gp3_storage_class ? 1 : 0
  
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = var.make_gp3_default ? "true" : "false"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    fsType    = "ext4"
    encrypted = "true"
  }

  depends_on = [
    helm_release.aws_ebs_csi_driver
  ]
}