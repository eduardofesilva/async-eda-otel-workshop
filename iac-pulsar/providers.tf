terraform {
  backend "s3" {
    bucket  = "your-s3-bucket"
    key     = "terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
  # Note: required_providers was moved to main.tf
}

provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

provider "null" {}

// Add these variables after the existing istio_version variable

