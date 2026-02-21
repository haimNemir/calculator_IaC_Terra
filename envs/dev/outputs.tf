output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "github_actions_role_arn" {
  value = module.github_oidc.role_arn
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "eks_oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}