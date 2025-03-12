# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

# Attach EKS Cluster Policy to the IAM Role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = var.eks_cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_cluster_version

  vpc_config {
    subnet_ids              = concat(aws_subnet.private[*].id, aws_subnet.public[*].id)
    endpoint_private_access = var.eks_endpoint_private_access
    endpoint_public_access  = var.eks_endpoint_public_access
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  # Ensure VPC resources are created first
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_vpc.main,
    aws_subnet.private,
    aws_subnet.public,
    aws_route_table.private,
    aws_route_table.public,
    aws_route_table_association.private,
    aws_route_table_association.public,
    aws_nat_gateway.nat,
    aws_internet_gateway.igw
  ]
}

# Security Group for EKS Cluster
resource "aws_security_group" "eks_cluster" {
  name        = "${var.project_name}-eks-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.main.id

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  # Pulsar Admin & WebSocket API
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Pulsar Admin & WebSocket API"
  }

  # Pulsar Service (Binary Protocol)
  ingress {
    from_port   = 6650
    to_port     = 6650
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Pulsar Binary Protocol"
  }

  # Pulsar Function Worker
  ingress {
    from_port   = 6651
    to_port     = 6651
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Pulsar Function Worker"
  }

  # BookKeeper client port
  ingress {
    from_port   = 3181
    to_port     = 3181
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "BookKeeper Client"
  }

  # ZooKeeper client port
  ingress {
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "ZooKeeper Client"
  }

  # Prometheus metrics
  ingress {
    from_port   = 8443
    to_port     = 8443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Prometheus Metrics"
  }

  # Allow all traffic within the same security group
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Allow all traffic within the security group"
  }

  tags = {
    Name = "${var.project_name}-eks-cluster-sg"
  }

  # Explicitly depend on VPC
  depends_on = [aws_vpc.main]
}

# Additional Security Group for Pulsar Services
resource "aws_security_group" "pulsar" {
  name        = "${var.project_name}-pulsar-sg"
  description = "Security group for Apache Pulsar services"
  vpc_id      = aws_vpc.main.id

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # BookKeeper internal ports
  ingress {
    from_port   = 3181
    to_port     = 3181
    protocol    = "tcp"
    self        = true
    description = "BookKeeper client port"
  }
  
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp" 
    self        = true
    description = "BookKeeper bookie server"
  }

  # ZooKeeper internal communication
  ingress {
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    self        = true
    description = "ZooKeeper client port"
  }
  
  ingress {
    from_port   = 2888
    to_port     = 2888
    protocol    = "tcp"
    self        = true
    description = "ZooKeeper peer communication"
  }
  
  ingress {
    from_port   = 3888
    to_port     = 3888
    protocol    = "tcp"
    self        = true
    description = "ZooKeeper leader election"
  }

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }
  
  # Pulsar broker
  ingress {
    from_port   = 6650
    to_port     = 6650
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Pulsar broker service port"
  }
  
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Pulsar web service port"
  }

  tags = {
    Name = "${var.project_name}-pulsar-sg"
  }

  depends_on = [aws_vpc.main]
}

# IAM Role for EKS Node Group
resource "aws_iam_role" "eks_node_group" {
  name = "${var.project_name}-eks-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Attach Node Group Policies to the IAM Role
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group.name
}

# EKS Node Group - simplified without launch template
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = aws_subnet.private[*].id
  
  # Specify a single instance type
  instance_types = ["m6i.xlarge"]
  
  # Disk size directly in the node group
  disk_size      = 60
  
  # Remove launch_template block completely

  scaling_config {
    desired_size = var.node_desired_size
    max_size     = var.node_max_size
    min_size     = var.node_min_size
  }

  update_config {
    max_unavailable = 1
  }

  # Basic capacity type
  capacity_type = "ON_DEMAND"

  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_readonly,
    aws_subnet.private,
    aws_route_table_association.private,
    aws_security_group.eks_nodes
  ]

  # Basic tags
  tags = {
    Name = "${var.project_name}-node-group"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "owned"
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      scaling_config[0].desired_size
    ]
  }
}

# IAM Policy and Role for VPC CNI
resource "aws_iam_policy" "vpc_cni_policy" {
  name        = "${var.project_name}-vpc-cni-policy"
  description = "IAM policy for VPC CNI addon"
  
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ec2:AssignPrivateIpAddresses",
          "ec2:AttachNetworkInterface",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeInstanceTypes",
          "ec2:DetachNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:UnassignPrivateIpAddresses"
        ],
        Resource = "*"
      }
    ]
  })
}

# IRSA for VPC CNI
resource "aws_iam_role" "vpc_cni" {
  name = "${var.project_name}-vpc-cni-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}"
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub": "system:serviceaccount:kube-system:aws-node",
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:aud": "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "vpc_cni_policy_attachment" {
  policy_arn = aws_iam_policy.vpc_cni_policy.arn
  role       = aws_iam_role.vpc_cni.name
}

# Add OIDC provider for the cluster
resource "aws_iam_openid_connect_provider" "eks_oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# AWS VPC CNI EKS Addon
resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "vpc-cni"
  addon_version            = data.aws_eks_addon_version.latest_cni.version
  resolve_conflicts        = "OVERWRITE"
  service_account_role_arn = aws_iam_role.vpc_cni.arn
  
  # Pre-create CNI configuration values
  configuration_values = jsonencode({
    enableNetworkPolicy: "true",
    env: {
      ENABLE_PREFIX_DELEGATION: "true",
      WARM_PREFIX_TARGET: "1"
    }
  })
  
  # Make sure the addon is installed after the node group and OIDC provider
  depends_on = [
    aws_eks_node_group.main,
    aws_iam_openid_connect_provider.eks_oidc
  ]
}