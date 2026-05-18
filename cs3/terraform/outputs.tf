output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "rds_endpoint" {
  value       = module.rds.rds_endpoint
  description = "RDS database endpoint (hostname:port)"
}

output "rds_database_name" {
  value       = module.rds.rds_database_name
  description = "RDS database name for employee records"
}

output "rds_security_group_id" {
  value = module.rds.rds_security_group_id
}

output "cognito_user_pool_id" {
  value       = module.cognito.user_pool_id
  description = "Cognito User Pool ID for authentication"
}

output "cognito_client_id" {
  value       = module.cognito.client_id
  description = "Cognito App Client ID"
}

output "cognito_client_secret" {
  value       = module.cognito.client_secret
  sensitive   = true
  description = "Cognito App Client Secret"
}

output "cognito_domain" {
  value = module.cognito.domain
}

output "cognito_auth_url" {
  value       = module.cognito.cognito_auth_url
  description = "Cognito authentication endpoint URL"
}

output "identity_pool_id" {
  value = aws_cognito_identity_pool.this.id
}

output "ecr_repository_url" {
  value       = module.ecr.ecr_repository_url
  description = "ECR repository URL for pushing portal container images"
}

output "ecr_repository_name" {
  value       = module.ecr.ecr_repository_name
  description = "ECR repository name for portal container"
}

output "cloudwatch_log_group" {
  value       = module.ecr.cloudwatch_log_group
  description = "CloudWatch log group for portal and Kubernetes logs"
}

output "loki_endpoint" {
  value       = module.logging.loki_endpoint
  description = "Loki log aggregation endpoint"
}

output "grafana_endpoint" {
  value       = module.logging.grafana_endpoint
  description = "Grafana visualization endpoint"
}

output "grafana_admin_user" {
  value       = module.logging.grafana_admin_user
  description = "Grafana admin username"
}

output "grafana_admin_password" {
  value       = module.logging.grafana_admin_password
  sensitive   = true
  description = "Grafana admin password (sensitive)"
}
