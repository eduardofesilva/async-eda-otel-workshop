# Output variables for Pulsar

output "pulsar_service_url" {
  description = "The URL to connect to Pulsar using the binary protocol"
  value       = "pulsar://${var.route53_config.pulsar_subdomain}.${var.route53_config.domain_name}:6650"
}

output "pulsar_websocket_url" {
  description = "The URL to connect to Pulsar using websockets"
  value       = "ws://${var.route53_config.pulsar_subdomain}.${var.route53_config.domain_name}:8000"
}

output "pulsar_secure_service_url" {
  description = "The secure URL to connect to Pulsar using the binary protocol (TLS)"
  value       = "pulsar+ssl://${var.route53_config.pulsar_subdomain}.${var.route53_config.domain_name}:6651"
}

output "pulsar_secure_websocket_url" {
  description = "The secure URL to connect to Pulsar using websockets (TLS)"
  value       = "wss://${var.route53_config.pulsar_subdomain}.${var.route53_config.domain_name}:8001"
}

output "pulsar_admin_url" {
  description = "The URL for the Pulsar Admin API"
  value       = "http://${var.route53_config.pulsar_subdomain}.${var.route53_config.domain_name}:8080"
}

output "pulsar_admin_secure_url" {
  description = "The secure URL for the Pulsar Admin API (TLS)"
  value       = "https://${var.route53_config.pulsar_subdomain}.${var.route53_config.domain_name}:8443"
}

output "pulsar_admin_console_url" {
  description = "The URL for the Pulsar Admin Console"
  value       = "https://${var.route53_config.pulsar_subdomain}.${var.route53_config.domain_name}"
}

# Output for debugging DNS records
output "pulsar_dns_hostname" {
  description = "The hostname that should be registered in Route53"
  value       = "${var.route53_config.pulsar_subdomain}.${var.route53_config.domain_name}"
}

# Output for getting token
output "get_token_command" {
  description = "Command to get the authentication token"
  value       = "kubectl get secret -n kaap-system token-superuser -o jsonpath='{.data.superuser\\.jwt}' | base64 --decode > pulsar-token.jwt"
}

# Output load balancer status
output "check_loadbalancer_command" {
  description = "Command to check the status of the load balancer"
  value       = "kubectl get svc -n kaap-system pulsar-proxy -o wide"
}

# Output the token for authentication (for convenience, real-world scenarios might not want to expose this)
output "token_retrieval_hint" {
  description = "Note about token retrieval"
  value       = "Run the get_token_command output to extract the authentication token to a file"
}