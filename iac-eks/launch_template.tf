# Launch Template for EKS Node Group - Simplified for core functionality
resource "aws_launch_template" "eks_nodes" {
  name        = "${var.project_name}-node-template"
  description = "Launch template for EKS worker nodes"

  # Use the EKS-optimized AMI
  image_id = data.aws_ami.eks_optimized.id
  
  # IMPORTANT: Remove the instance_type - this is what's causing the error
  # instance_type = var.node_instance_types[0]
  
  # Set appropriate instance metadata options for security
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 required
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
  
  # Security Groups
  vpc_security_group_ids = [aws_security_group.eks_nodes.id]
  
  # Simple bootstrap script
  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -ex
    /etc/eks/bootstrap.sh ${var.eks_cluster_name} \
      --b64-cluster-ca ${aws_eks_cluster.main.certificate_authority[0].data} \
      --apiserver-endpoint ${aws_eks_cluster.main.endpoint} \
      --container-runtime containerd
  EOF
  )
  
  # Root EBS volume
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  # Basic tags
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-worker-node"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${var.project_name}-worker-volume"
    }
  }

  tag_specifications {
    resource_type = "network-interface"
    tags = {
      Name = "${var.project_name}-worker-network-interface"
    }
  }
}
