
# -------------------------
# Provider Block
# -------------------------

provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
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

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}


# -------------------------
# VPC Module
# -------------------------

module "vpc" {
  source = "./modules/terraform-aws-vpc-6.4.0"

  name = "${var.cluster_name}-vpc"
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
    "karpenter.sh/discovery"                    = var.cluster_name
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
    "karpenter.sh/discovery"                    = var.cluster_name
  }
}

# -------------------------
# EKS Cluster
# -------------------------

module "eks" {
  source                 = "./modules/terraform-aws-eks-21.3.2"
  name                   = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  endpoint_public_access = var.eks_public_access_enabled
  endpoint_private_access                  = true
  enable_cluster_creator_admin_permissions = true

  # -------------------------
  # EKS Add-ons
  # -------------------------  

  addons = {
    coredns = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
  }
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  # -------------------------
  # Node Groups (Spot only)
  # -------------------------

  eks_managed_node_groups = {
    karpenter = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.instance_types
      capacity_type  = "SPOT"
      min_size       = var.min_size
      max_size       = var.max_size
      desired_size   = var.desired_size

      labels = {
        "karpenter.sh/controller" = "true"
      }
    }
  }
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }


  tags = {
    cluster = var.cluster_name
  }
}

# -------------------------
# Karpenter
# -------------------------

module "karpenter" {
  source       = "./modules/terraform-aws-eks-21.3.2/modules/karpenter"
  cluster_name = var.cluster_name

  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = "${var.cluster_name}-karpenter"
  create_pod_identity_association = true

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
  tags = {

    "karpenter.sh/discovery" = module.eks.cluster_name

  }
  depends_on = [
    module.eks
  ]
}

# -------------------------
# Bastion Security Group
# -------------------------
module "bastion_sg" {
  source      = "./modules/terraform-aws-security-group-5.3.0"
  name        = "${var.cluster_name}-bastion-sg"
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
  source                      = "./modules/terraform-aws-ec2-instance-6.1.1"
  name                        = "${var.cluster_name}-bastion"
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.bastion_instance_types
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
