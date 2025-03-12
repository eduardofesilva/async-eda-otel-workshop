# IaC EKS - OpenTelemetry Event-Driven Architecture Infrastructure

This directory contains Terraform Infrastructure as Code (IaC) configurations to deploy the required AWS infrastructure for the OpenTelemetry Event-Driven Architecture project, including an Amazon EKS cluster and all associated resources.

## Architecture Overview

This IaC creates the following resources:

- **VPC** with public and private subnets across multiple availability zones
- **EKS Cluster** with managed node groups
- **IAM Roles** and policies for cluster and node groups
- **Security Groups** for cluster communication
- **AWS Load Balancer Controller** for managing ALBs/NLBs
- **VPC CNI** plugin for pod networking
- **EBS CSI Driver** for persistent storage
- **Route53** DNS configurations

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. **AWS CLI** installed and configured with appropriate credentials
   ```bash
   aws configure
   ```

2. **Terraform** (v1.0 or later) installed
   ```bash
   terraform -v
   ```

3. **kubectl** installed for interacting with the Kubernetes cluster
   ```bash
   kubectl version --client
   ```

4. **Helm** (v3.0 or later) installed for deploying Kubernetes applications
   ```bash
   helm version
   ```

5. **AWS Permissions**: Your AWS user/role must have permissions to create:
   - VPC and networking resources
   - IAM roles and policies
   - EKS clusters and node groups
   - Route53 record sets

6. **S3 Bucket** for Terraform state (already created)

7. **Route53 Hosted Zone** already set up for your domain

## How to Deploy

### 1. Configure Terraform Variables

1. Update the `terraform.tfvars` file with your specific values:
   ```bash
   nano terraform.tfvars
   ```

   Required values:
   - `domain_name`: Your domain name (e.g., example.com)
   - `eks_cluster_name`: Name for your EKS cluster
   - `route53_zone_id`: Your Route53 hosted zone ID

2. Update the S3 backend configuration in `provider.tf`:
   ```bash
   nano provider.tf
   ```
   
   Change:
   ```hcl
   terraform {
     backend "s3" {
       bucket  = "your-s3-bucket"
       key     = "terraform.tfstate"
       region  = "us-east-1"
       encrypt = true
     }
   }
   ```
   
   To match your actual S3 bucket name and desired region.

### 2. Initialize Terraform
```bash
terrraform init
```

### 3. Plan Terraform
```bash
terrraform plan
```

### 4. Apply Terraform
```bash
terrraform apply -autoa-approve
```
