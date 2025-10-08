variable "kubernetes_version" {
  description = "kubernetes version"
  type        = string
}
variable "vpc_cidr" {
  description = "default CIDR range of the VPC"
  type        = string
}
variable "aws_region" {
  description = "aws region"
  type        = string
}
variable "cluster_name" {
  description = "The name of the EKS cluster"
  type        = string
}
variable "bucket_name" {
  description = "The name of the S3 bucket"
  type        = string
}
variable "environment" {
  description = "The deployment environment (e.g., dev, staging, prod)"
  type        = string
}
variable "worker_mgmt_ingress_cidrs" {
  type = list(string)
}
variable "private_subnets" {
  description = "List of private subnet CIDR blocks"
  type        = list(string)
}
variable "public_subnets" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
}

variable "ssh_key_name" {
  description = "EC2 Key pair name for SSH access"
  type        = string
}

variable "eks_admin_user_arn" {
  description = "IAM ARN of the user to be granted admin access to the EKS cluster"
  type        = string
}

variable "eks_admin_username" {
  description = "Username to assign in the EKS cluster for the IAM user"
  type        = string
  default     = "eks-admin"
}

