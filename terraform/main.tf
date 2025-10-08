provider "aws" {
  region = var.aws_region
}
data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}
locals {
  iam_username = split("/", data.aws_caller_identity.current.arn)[1]
}

# -------------------------
# Label Module
# -------------------------

module "label" {
  source      = "./modules/terraform-null-label"
  name        = var.cluster_name
  environment = var.environment
}

# -------------------------
# VPC Module
# -------------------------
module "vpc" {
  source               = "./modules/vpc"
  name                 = "${module.label.environment}-vpc"
  cidr                 = var.vpc_cidr
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = var.private_subnets
  public_subnets       = var.public_subnets
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
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}


#---------------
# Bastion Host 
#---------------

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# -------------------------
# Bastion Security Group
# -------------------------
resource "aws_security_group" "bastion_sg" {
  name        = "${module.label.id}-bastion-sg"
  description = "Security group for Bastion host"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow SSH access from your IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${module.label.id}-bastion-sg"
  }
}

# -------------------------
# Bastion Host EC2 Instance
# -------------------------
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  key_name                    = var.ssh_key_name
  associate_public_ip_address = true

  tags = {
    Name = "${module.label.id}-bastion"
  }
}


# -------------------------
# EKS Cluster
# -------------------------

module "eks" {
  source                          = "./modules/eks"
  cluster_name                    = module.label.id
  cluster_version                 = var.kubernetes_version
  subnet_ids                      = module.vpc.private_subnets
  vpc_id                          = module.vpc.vpc_id
  enable_irsa                     = true
  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true

  tags = {
    cluster = var.cluster_name
  }
  access_entries = {
    user_access = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${local.iam_username}"

      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
          access_scope = { type = "cluster" }
        }

        cluster_admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
}
