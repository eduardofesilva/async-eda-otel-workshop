# Apache Pulsar on Kubernetes with KAAP

This project contains Terraform code for deploying a production-grade Apache Pulsar cluster on Kubernetes using KAAP (Kubernetes Apache Pulsar Operator). It provides an end-to-end infrastructure deployment including all necessary AWS resources and Kubernetes components.

## Overview

This deployment creates:

- Apache Pulsar cluster with configurable components (ZooKeeper, BookKeeper, Broker, Proxy)
- AWS Load Balancer Controller for exposing services
- EBS CSI Driver for persistent storage
- Certificate Manager for TLS certificates
- External DNS for automatic DNS record management
- Proper IAM roles and policies for security

## Prerequisites

- An existing EKS cluster
- AWS CLI configured with appropriate permissions
- kubectl installed and configured to access your EKS cluster
- Terraform v1.0.0+ installed
- A Route53 hosted zone for your domain
- Helm v3 installed

## Required Variables

The deployment requires several variables to be defined. The key variables include:

### General Settings
- `cluster_name`: Name of your EKS cluster
- `region`: AWS region for deployment
- `aws_profile`: AWS profile for authentication

### Route53 Configuration
- `route53_config.domain_name`: Your domain name (e.g., example.com)
- `route53_config.hosted_zone_id`: Your Route53 hosted zone ID
- `route53_config.email`: Email for Let's Encrypt notifications
- `route53_config.pulsar_subdomain`: Subdomain for Pulsar (e.g., "pulsar" for pulsar.example.com)

### Pulsar Configuration
- `kaapConfig.pulsar_image_tag`: Apache Pulsar image version
- `kaapConfig.zookeeper_count`: Number of ZooKeeper nodes
- `kaapConfig.bookkeeper_count`: Number of BookKeeper nodes
- `kaapConfig.broker_count`: Number of Broker nodes
- `kaapConfig.proxy_count`: Number of Proxy nodes
- `kaapConfig.internal_lb`: Whether to use an internal load balancer

### Sensitive Data
- `secretConfig.pulsar_admin_console_username`: Admin username
- `secretConfig.pulsar_admin_console_password`: Admin password

## How to Run

1. **Initialize Terraform**
   ```bash
   terraform init
   ```

2. **Review the deployment plan**
   ```bash
   terraform plan -var-file=terraform.tfvars
   ```

3. **Apply the configuration**
   ```bash
   terraform apply -var-file=terraform.tfvars
   ```

4. **Verify the deployment**
   ```bash
   kubectl get pods -n kaap-system
   kubectl get pulsarcluster -n kaap-system
   kubectl get svc -n kaap-system
   ```

5. **Access Pulsar Admin Console**
   
   Once the deployment completes, you can access the Pulsar Admin Console at:
   ```
   https://<pulsar_subdomain>.<domain_name>/admin/
   ```
   
   Log in using the credentials specified in the `secretConfig` variables.

## Expected Outputs

After a successful deployment, you should see:

1. **Pulsar Components Running**: 
   - ZooKeeper pods (number specified by `zookeeper_count`)
   - BookKeeper pods (number specified by `bookkeeper_count`)
   - Broker pods (number specified by `broker_count`)
   - Proxy pods (number specified by `proxy_count`)
   - Pulsar Admin Console pod
   
2. **Load Balancer**: 
   - AWS Network Load Balancer provisioned for the Pulsar Proxy service
   - DNS record automatically created for your Pulsar cluster
   
3. **Storage**: 
   - EBS volumes automatically provisioned for ZooKeeper and BookKeeper

4. **Security**:
   - TLS certificates generated via cert-manager
   - Authentication enabled with token-based auth
   - IAM roles and policies properly configured

## Troubleshooting

### Common Issues

1. **Pods in Pending State**:
   - Check PVCs: `kubectl get pvc -n kaap-system`
   - Verify EBS CSI driver: `kubectl get pods -n kube-system | grep ebs`

2. **Certificate Issues**:
   - Check cert-manager issuers: `kubectl get clusterissuers`
   - Check certificate status: `kubectl get certificates -n kaap-system`

3. **Load Balancer Not Provisioned**:
   - Verify AWS Load Balancer controller: `kubectl get pods -n kube-system | grep aws-load-balancer-controller`
   - Check service: `kubectl get svc -n kaap-system | grep proxy`

4. **DNS Not Resolving**:
   - Check External DNS: `kubectl get pods -n external-dns`
   - Verify logs: `kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns`

### Accessing Logs

```bash
# Check operator logs
kubectl logs -n kaap-system -l app.kubernetes.io/name=kaap-operator

# Check proxy logs
kubectl logs -n kaap-system -l app=pulsar-proxy
```

## Cleanup

To destroy all resources created by this Terraform configuration:

```bash
terraform destroy -var-file=terraform.tfvars
```

**Note**: This will not remove any data stored in Pulsar. If you want to completely clean up, you may need to manually delete PVCs and their associated EBS volumes.

## Additional Resources

- [KAAP Documentation](https://github.com/datastax/kaap)
- [Apache Pulsar Documentation](https://pulsar.apache.org/docs/en/next/)
- [Kubernetes Apache Pulsar Operator](https://github.com/datastax/kaap)

