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

# -------------------------
# EKS Cluster Module
# -------------------------

# module "eks" {
  # source                          = "./modules/eks"
  # cluster_name                    = module.label.id
  # cluster_version                 = var.kubernetes_version
  # subnet_ids                      = module.vpc.private_subnets
  # vpc_id                          = module.vpc.vpc_id
  # enable_irsa                     = true
  # cluster_endpoint_public_access  = false
  # cluster_endpoint_private_access = true

  # tags = {
    # cluster = var.cluster_name
  # }

  # access_entries = {
    # user_access = {
      # principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${local.iam_username}"

      # policy_associations = {
        # admin = {
          # policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy"
          # access_scope = { type = "cluster" }
        # }

        # cluster_admin = {
          # policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          # access_scope = { type = "cluster" }
        # }
      # }
    # }
  # }
# }
# -------------------------
# EKS Cluster Module
# -------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.3.0"

  name                            = module.label.id
  kubernetes_version              = var.kubernetes_version
  subnet_ids                      = module.vpc.private_subnets
  vpc_id                          = module.vpc.vpc_id
  enable_irsa                     = true
  endpoint_public_access  = false
  endpoint_private_access = true
  node_groups = {}
  tags = {
    cluster = var.cluster_name
  }
#-------------------------------------
# Access for current IAM user
#-------------------------------------
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
# -------------------------
# Karpenter configuration
# -------------------------
module "karpenter" {
  source  = "aws-ia/karpenter/aws"
  version = "2.8.0"

  cluster_name = module.eks.cluster_name
  cluster_endpoint = module.eks.cluster_endpoint
  cluster_certificate_authority_data = module.eks.cluster_certificate_authority_data
  subnets = module.vpc.private_subnets
  service_account_name = "karpenter"
  service_account_namespace = "karpenter"

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# -------------------------
# Karpenter Submodule
# -------------------------
# module "eks_karpenter" {
  # source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  # version = "21.3.1"
  # cluster_name             = module.eks.cluster_id

  # tags = {
    # "kubernetes.io/cluster/${module.label.id}" = "owned"
  # }
# }