#  AWS EKS Cluster Deployment with Karpenter and Bastion Host  
*Automated with Terraform and GitHub Actions*

This project provisions a **fully managed AWS EKS Cluster** with **Karpenter** for intelligent node provisioning and an **EC2 Bastion Host** for private access.  
Infrastructure deployment and teardown are automated using **Terraform** and **GitHub Actions**.

---

##  Architecture Overview

**Components Deployed:**
-  VPC with private/public subnets, NAT Gateway, and DNS enabled  
-  EKS Cluster (private API access enabled)  
-  Karpenter for autoscaling EC2 nodes  
-  Bastion EC2 Instance for secure access  
-  S3 Backend for Terraform remote state  
-  GitHub Actions for CI/CD automation

---

##  Repository Structure


├── terraform/
│     ├── main.tf
│     ├── variables.tf
│     ├── outputs.tf
│     ├── terraform.tfvars
│     ├── K8s/
│     │    └── karpenter/
│     │           └── karpenter-provisioners.yaml
│     └── modules/
│           ├── terraform-aws-vpc-6.4.0/
│           ├── terraform-aws-eks-21.3.2/
│           ├── terraform-aws-security-group-5.3.0/
│           └── terraform-aws-ec2-instance-6.1.1/
└── .github/
      └── workflows/
            ├── deploy-eks.yml
            └── destroy-all.yml

---

## Key Terraform Variables

| Variable | Description | Example |
|-----------|--------------|----------|
| `kubernetes_version` | EKS Kubernetes version | `"1.33"` |
| `aws_region` | AWS region | `"us-east-1"` |
| `vpc_cidr` | VPC CIDR range | `"10.0.0.0/16"` |
| `cluster_name` | Cluster name | `"poc-cluster"` |
| `bucket_name` | S3 bucket for state | `"poc-tfstate-bucket-0123456"` |
| `environment` | Environment tag | `"sit"` |
| `ssh_key_name` | EC2 SSH key name | `"test01"` |
| `eks_public_access_enabled` | Public access for Karpenter setup | `true` |
| `private_subnets` | List of private subnets | `["10.0.1.0/24", "10.0.2.0/24"]` |
| `public_subnets` | List of public subnets | `["10.0.4.0/24", "10.0.5.0/24"]` |
| `instance_types` | Worker node instance types | `["t3.medium", "t3.small"]` |
| `bastion_instance_types` | Bastion EC2 instance type | `"t3.micro"` |
| `min_size` | Minimum nodes | `"2"` |
| `max_size` | Maximum nodes | `"4"` |
| `desired_size` | Desired nodes | `"2"` |

---

##  Deployment Instructions

### **1. Prerequisites**
- AWS account with IAM admin credentials  
- Terraform ≥ 1.4.0  
- S3 bucket for Terraform backend  
- GitHub repository with secrets configured:  
  - `AWS_ACCESS_KEY_ID`  
  - `AWS_SECRET_ACCESS_KEY`  
  - `AWS_REGION`

---
## GitHub Actions Workflows
### Deploy Workflow

File: .github/workflows/deploy-eks.yml

This workflow provisions:
VPC, EKS, Bastion host
Installs Karpenter via Helm
Applies NodeClass and NodePool manifests
Manual Trigger
From the Actions tab → Select “Deploy EKS and Karpenter” → Click Run workflow

### Destroy Workflow

File: .github/workflows/destroy-all.yml

This workflow tears down all Terraform-managed resources.
Manual Trigger
From the Actions tab → Select “Destroy all” → Click Run workflow
