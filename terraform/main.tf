
# -------------------------
# Provider Block
# -------------------------

provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}
# -------------------------
# Data Block
# -------------------------

data "aws_availability_zones" "available" {}

data "aws_caller_identity" "current" {}
locals {
  iam_username = split("/", data.aws_caller_identity.current.arn)[1]
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# -------------------------
# Label Module
# -------------------------

module "label" {
  source      = "cloudposse/label/null"
  version     = "0.25.0"
  name        = var.cluster_name
  environment = var.environment
}

# -------------------------
# VPC Module
# -------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.4.0"

  name = "${module.label.environment}-vpc"
  cidr = var.vpc_cidr

  azs             = data.aws_availability_zones.available.names
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "Environment"                               = var.environment

  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
    "karpenter.sh/discovery"                    = "${module.label.environment}-EKS-cluster"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
    "karpenter.sh/discovery"                    = "${module.label.environment}-EKS-cluster"
  }
}


# -------------------------
# EKS Cluster
# -------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.3.2"

  name                                     = "${module.label.environment}-EKS-cluster"
  kubernetes_version                       = var.kubernetes_version
  endpoint_public_access                   = false
  endpoint_private_access                  = true
  enable_cluster_creator_admin_permissions = true

  create_auto_mode_iam_resources = false
  compute_config = {
    enabled = false
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  tags = {
    cluster                  = var.cluster_name
    "karpenter.sh/discovery" = "${module.label.environment}-EKS-cluster"
  }
}

# -------------------------
# Karpenter Custom Resources
# -------------------------

# Define the EC2NodeClass, which specifies AWS-specific configurations for nodes
resource "kubectl_manifest" "ec2_node_class_general_purpose" {
  yaml_body  = <<-YAML
    apiVersion: karpenter.k8s.aws/v1beta1
    kind: EC2NodeClass
    metadata:
      name: general-purpose
      namespace: karpenter
    spec:
      amiFamily: AL2023
      role: ${module.eks.karpenter_node_iam_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: "${module.label.environment}-EKS-cluster"
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: "${module.label.environment}-EKS-cluster"
  YAML
  depends_on = [module.eks]
}

# Define the NodePool, which defines Karpenter's scheduling and provisioning logic
resource "kubectl_manifest" "node_pool_general_purpose" {
  yaml_body  = <<-YAML
    apiVersion: karpenter.sh/v1beta1
    kind: NodePool
    metadata:
      name: general-purpose
      namespace: karpenter
    spec:
      template:
        spec:
          nodeClassRef:
            name: general-purpose
          requirements:
            - key: "kubernetes.io/arch"
              operator: In
              values: ["amd64"]
            - key: "kubernetes.io/os"
              operator: In
              values: ["linux"]
            - key: "karpenter.sh/capacity-type"
              operator: In
              values: ["on-demand", "spot"]
            - key: "karpenter.k8s.aws/instance-family"
              operator: In
              values: ["t2", "t3"]
      limits:
        cpu: "1000"
      disruption:
        consolidationPolicy: WhenUnderutilized
        consolidateAfter: 60s
  YAML
  depends_on = [kubectl_manifest.ec2_node_class_general_purpose]
}


# -------------------------
# Bastion Security Group
# -------------------------
module "bastion_sg" {

  #source  = "terraform-aws-modules/security-group/aws"
  #version = "~> 5.0"
  source      = "./modules/terraform-aws-security-group-5.3.0"
  name        = "${module.label.environment}-bastion-sg"
  description = "Security group for Bastion host"
  vpc_id      = module.vpc.vpc_id

  # SSH from your IP
  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "SSH access"
    }
  ]

  # Outbound to reach private EKS API
  egress_with_cidr_blocks = [
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "HTTPS to private EKS"
    },
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
      description = "Allow all outbound"
    }
  ]

  tags = {
    Name = "${var.environment}-bastion-sg"
  }
}

# -------------------------
# Bastion EC2 Module
# -------------------------

module "bastion_ec2" {
  source                      = "terraform-aws-modules/ec2-instance/aws"
  version                     = "6.1.1"
  name                        = "${module.label.environment}-bastion"
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  key_name                    = var.ssh_key_name
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [module.bastion_sg.security_group_id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y curl unzip

    # AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install

    # kubectl latest
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
  EOF

  tags = {
    Name = "${var.environment}-bastion"
  }
}

# -------------------------
# EKS SG rule to allow Bastion access
# -------------------------
resource "aws_security_group_rule" "allow_bastion_to_eks" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = module.eks.cluster_security_group_id
  source_security_group_id = module.bastion_sg.security_group_id
  description              = "Allow Bastion access to private EKS API"
}