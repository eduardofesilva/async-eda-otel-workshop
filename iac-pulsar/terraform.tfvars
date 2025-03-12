# General cluster configuration
cluster_name = "otel-eda-cluster"
region       = "us-east-1"

# KAAP configuration
kaapConfig = {
  # Pulsar image to use - use a stable version for production
  pulsar_image_tag = "apachepulsar/pulsar:2.10.2"
  
  # Component counts - increase for production
  zookeeper_count  = 3     # Odd number for quorum (3 for small, 5 for larger deployments)
  bookkeeper_count = 3     # At least 3 for redundancy
  broker_count     = 2     # Scale based on throughput needs
  proxy_count      = 2     # Scale based on client connection needs
  
  # Logging configuration
  log_level = "info"       # Options: debug, info, warn, error
  
  # Admin console credentials - change these!
  pulsar_admin_console_username = "admin"
  pulsar_admin_console_password = ""
  
  # Load balancer configuration
  internal_lb = false      # Set to true for private clusters
}

# Secret configuration (sensitive values)
secretConfig = {
  pulsar_admin_console_username = "admin"
  pulsar_admin_console_password = ""
}

# Route53 configuration for cert-manager
route53_config = {
  region           = "us-east-1"
  domain_name      = ""      # Your domain name
  hosted_zone_id   = ""   # Your Route53 hosted zone ID
  email            = ""
  pulsar_subdomain = "pulsar"           # Will create pulsar.example.com
}

# Cert-manager configuration
cert_manager_namespace = "cert-manager"
cert_manager_set_resources = true
cert_manager_replicas = 1
cert_manager_cpu_request = "100m"
cert_manager_memory_request = "128Mi"
cert_manager_cpu_limit = "200m"
cert_manager_memory_limit = "256Mi"


# Istio configuratio