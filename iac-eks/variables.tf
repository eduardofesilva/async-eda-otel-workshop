# General Variables
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project used for resource naming"
  type        = string
  default     = "otel-eda"
}

# VPC Variables
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_dns_support" {
  description = "Enable DNS support in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "public_subnet_count" {
  description = "Number of public subnets to create"
  type        = number
  default     = 2
}

variable "private_subnet_count" {
  description = "Number of private subnets to create"
  type        = number
  default     = 2
}

variable "public_subnet_cidr_prefix" {
  description = "CIDR prefix for public subnets"
  type        = string
  default     = "10.0"
}

variable "private_subnet_cidr_prefix" {
  description = "CIDR prefix for private subnets"
  type        = string
  default     = "10.0"
}

variable "private_subnet_cidr_offset" {
  description = "CIDR offset for private subnets"
  type        = number
  default     = 10
}

# EKS Variables
variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "eks_cluster_version" {
  description = "Version of the EKS cluster"
  type        = string
  default     = "1.30"
}

variable "eks_endpoint_private_access" {
  description = "Enable private access to the EKS cluster endpoint"
  type        = bool
  default     = true
}

variable "eks_endpoint_public_access" {
  description = "Enable public access to the EKS cluster endpoint"
  type        = bool
  default     = true
}

variable "node_group_name" {
  description = "Name of the EKS node group"
  type        = string
  default     = "otel-eda-node-group"
}

variable "node_instance_types" {
  description = "Instance types for the EKS node group"
  type        = list(string)
  default     = ["m6i.xlarge"]
}

variable "node_disk_size" {
  description = "Disk size in GB for EKS nodes"
  type        = number
  default     = 60  # Set back to 60GB as requested
}

variable "node_desired_size" {
  description = "Desired number of nodes in the EKS node group"
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Maximum number of nodes in the EKS node group"
  type        = number
  default     = 5
}

variable "node_min_size" {
  description = "Minimum number of nodes in the EKS node group"
  type        = number
  default     = 1
}

variable "aws_lb_controller_version" {
  description = "Version of the AWS Load Balancer Controller to deploy"
  type        = string
  default     = "1.5.3"
}

variable "aws_vpc_cni_version" {
  description = "Version of the AWS VPC CNI to deploy"
  type        = string
  default     = "1.1.17"
}

variable "aws_ebs_csi_driver_version" {
  description = "Version of the AWS EBS CSI Driver to deploy"
  type        = string
  default     = "2.17.1"
}

# Route53 Variables
variable "route53_zone_id" {
  description = "ID of the Route53 hosted zone"
  type        = string
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

# S3 Backend Variables
variable "terraform_state_bucket" {
  description = "S3 bucket for Terraform state"
  type        = string
  default     = ""
}

variable "terraform_state_key" {
  description = "Key for Terraform state file"
  type        = string
  default     = "terraform.tfstate"
}
