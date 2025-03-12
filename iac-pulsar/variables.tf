variable "cluster_name" {
  description = "Name of the EKS cluster to retrieve information from"
  type        = string
  default     = "otel-eda-cluster"
}

variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS profile to use for authentication"
  type        = string
  default     = "default"
}

variable "aws_lb_controller_chart_version" {
  description = "AWS Load Balancer Controller Helm chart version"
  type        = string
  default     = "1.4.8"
}

# EBS CSI Driver

## EBS CSI Driver variables
variable "aws_ebs_csi_driver_chart_version" {
  description = "AWS EBS CSI Driver Helm chart version"
  type        = string
  default     = "2.16.0"
}

variable "enable_volume_resizing" {
  description = "Enable volume resizing feature for the EBS CSI Driver"
  type        = bool
  default     = true
}

variable "enable_volume_snapshot" {
  description = "Enable volume snapshot feature for the EBS CSI Driver"
  type        = bool
  default     = true
}

variable "ebs_csi_controller_replicas" {
  description = "Number of EBS CSI controller replicas"
  type        = number
  default     = 2
}

variable "set_controller_resources" {
  description = "Set resource requests/limits for controller"
  type        = bool
  default     = false
}

variable "controller_cpu_request" {
  description = "Controller CPU request"
  type        = string
  default     = "100m"
}

variable "controller_memory_request" {
  description = "Controller memory request"
  type        = string
  default     = "128Mi"
}

variable "controller_cpu_limit" {
  description = "Controller CPU limit"
  type        = string
  default     = "200m"
}

variable "controller_memory_limit" {
  description = "Controller memory limit"
  type        = string
  default     = "256Mi"
}

variable "create_gp3_storage_class" {
  description = "Create a storage class for gp3 volumes"
  type        = bool
  default     = true
}

variable "make_gp3_default" {
  description = "Make the gp3 storage class the default"
  type        = bool
  default     = false
}

# Cert Manager

# Cert Manager variables
variable "cert_manager_namespace" {
  description = "Namespace for cert-manager"
  type        = string
  default     = "cert-manager"
}

variable "cert_manager_version" {
  description = "Version of cert-manager CRDs to install"
  type        = string
  default     = "v1.12.0"
  validation {
    condition     = !startswith(var.cert_manager_version, "vv")
    error_message = "The cert_manager_version should not start with 'vv'."
  }
}

variable "cert_manager_email" {
  description = "Email address for Let's Encrypt notifications"
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the domain"
  type        = string
  default     = ""
}

variable "cert_manager_set_resources" {
  description = "Set resource requests/limits for cert-manager"
  type        = bool
  default     = false
}

variable "cert_manager_cpu_request" {
  description = "Cert Manager CPU request"
  type        = string
  default     = "100m"
}

variable "cert_manager_memory_request" {
  description = "Cert Manager memory request"
  type        = string
  default     = "128Mi"
}

variable "cert_manager_cpu_limit" {
  description = "Cert Manager CPU limit"
  type        = string
  default     = "200m"
}

variable "cert_manager_memory_limit" {
  description = "Cert Manager memory limit"
  type        = string
  default     = "256Mi"
}

variable "cert_manager_replicas" {
  description = "Number of cert-manager controller replicas"
  type        = number
  default     = 1
}



# Route53 configuration for Let's Encrypt DNS01 challenge
variable "route53_config" {
  description = "AWS Route53 configuration for cert-manager"
  type = object({
    region                = string
    domain_name           = string
    hosted_zone_id        = string
    email                 = string
    pulsar_subdomain      = string
  })
}

variable "kaapConfig" {
  description = "Configuration for KAAP deployment"
  type = object({
    pulsar_image_tag  = string
    zookeeper_count   = number
    bookkeeper_count  = number
    broker_count      = number
    proxy_count       = number
    log_level         = string
    pulsar_admin_console_username = string
    pulsar_admin_console_password = string
    internal_lb       = bool
  })
  
  default = {
    pulsar_image_tag  = "apachepulsar/pulsar:2.10.2"
    zookeeper_count   = 3
    bookkeeper_count  = 3
    broker_count      = 2
    proxy_count       = 2
    log_level         = "info"
    pulsar_admin_console_username = "admin"
    pulsar_admin_console_password = "password" # Should be overridden in tfvars
    internal_lb       = false
  }
}

variable "secretConfig" {
  description = "Secret configuration for KAAP"
  type = object({
    pulsar_admin_console_username = string
    pulsar_admin_console_password = string
  })
  
  sensitive = true
}

variable "cert_manager_chart_version" {
  description = "Version of the cert-manager Helm chart to install"
  type        = string
  default     = "v1.12.0"  # Update to latest stable version
}

variable "external_dns_chart_version" {
  description = "Version of the external-dns Helm chart to install"
  type        = string
  default     = "1.13.1"
}