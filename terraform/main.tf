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

# ------------------------------------------------------------------
# Karpenter Controller IAM Role for ServiceAccount (IRSA)
# ------------------------------------------------------------------

module "karpenter_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.46.0"

  role_name_prefix                   = "${module.eks.cluster_name}-karpenter"
  attach_karpenter_controller_policy = true

  oidc_providers = {
    eks = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }
}

# ------------------------------------------------------------------
# Karpenter Helm Chart
# ------------------------------------------------------------------

resource "helm_release" "karpenter" {
  name       = "${module.label.id}-karpenter"
  repository = "oci://public.ecr.aws/karpenter/karpenter"
  chart      = "karpenter"
  version    = "v0.37.0"

  namespace        = "karpenter"
  create_namespace = true

  set {
    name  = "settings.clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "settings.clusterEndpoint"
    value = module.eks.cluster_endpoint
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.karpenter_irsa.iam_role_arn
  }

  set {
    name  = "settings.interruptionQueue"
    value = module.eks.cluster_name
  }
}

# ------------------------------------------------------------------
# Karpenter Node IAM Role
# ------------------------------------------------------------------

module "karpenter_node_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "5.46.0"

  name = "${module.label.id}-karpenter-node"
  assume_role_policy_statements = [
    {
      actions = ["sts:AssumeRole"]
      principals = [
        {
          type        = "Service"
          identifiers = ["ec2.amazonaws.com"]
        }
      ]
    }
  ]

  policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
}




# # -------------------------
# # EKS Cluster Module
# # -------------------------
# module "eks" {
# source  = "terraform-aws-modules/eks/aws"
# version = "21.3.1"

# name                            = module.label.id
# kubernetes_version              = var.kubernetes_version
# subnet_ids                      = module.vpc.private_subnets
# vpc_id                          = module.vpc.vpc_id
# enable_irsa                     = true
# endpoint_public_access  = false
# endpoint_private_access = true
# #  tags = {
# #    cluster = var.cluster_name
# #  }
# #-------------------------------------
# # Access for current IAM user
# #-------------------------------------
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

# # -------------------------
# # Karpenter Submodule
# # -------------------------
# module "eks_karpenter" {
# source  = "terraform-aws-modules/eks/aws//modules/karpenter"
# version = "21.3.1"
# cluster_name             = module.eks.cluster_id

# tags = {
# "kubernetes.io/cluster/${module.label.id}" = "owned"
# }
# }
