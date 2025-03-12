# Security Group for EKS Worker Nodes - Essential configuration only
resource "aws_security_group" "eks_nodes" {
  name        = "${var.project_name}-eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Required kubelet ports
  ingress {
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
    description     = "Kubelet API"
  }

  # Allow all traffic from the EKS control plane security group
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.eks_cluster.id]
    description     = "Allow all traffic from EKS control plane"
  }

  # Allow all traffic within the same security group (node to node)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Allow traffic between worker nodes"
  }

  # Allow NodePort service range (30000-32767)
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Kubernetes NodePort service port range"
  }
  
  # Allow access to specific ports for health checks
  ingress {
    from_port   = 0 
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
    description = "Allow VPC CIDR blocks to access all ports (including health checks)"
  }

  tags = {
    Name = "${var.project_name}-eks-nodes-sg"
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "owned"
  }
}

# Update the EKS cluster security group to allow traffic to worker nodes
resource "aws_security_group_rule" "cluster_to_nodes" {
  security_group_id        = aws_security_group.eks_cluster.id
  type                     = "egress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  source_security_group_id = aws_security_group.eks_nodes.id
  description              = "Allow cluster to communicate with worker nodes"
}
