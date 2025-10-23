output "cluster_id" {
  description = "EKS cluster ID."
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane."
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane."
  value       = module.eks.cluster_security_group_id
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "S3_Bucket_Name" {
  description = "AWS S3_Bucket Name"
  value       = var.bucket_name
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "iam_username" {
  value = local.iam_username
}
output "bastion_public_ip" {
  description = "Public IP of the Bastion host"
  value       = module.bastion_ec2.public_ip
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}


