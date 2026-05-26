output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "ec2_instance_id" {
  value       = module.ec2_k3s.instance_id
  description = "EC2 instance ID running k3s"
}

output "ec2_instance_public_ip" {
  value       = module.ec2_k3s.instance_public_ip
  description = "Public Elastic IP for EC2 instance"
}

output "ec2_instance_private_ip" {
  value       = module.ec2_k3s.instance_private_ip
  description = "Private IP of EC2 instance"
}

output "kubernetes_endpoint" {
  value       = module.ec2_k3s.kubernetes_endpoint
  description = "k3s API endpoint"
}

output "grafana_endpoint" {
  value       = module.ec2_k3s.grafana_endpoint
  description = "Grafana monitoring dashboard URL"
}

output "postgresql_endpoint" {
  value       = module.ec2_k3s.postgresql_endpoint
  description = "PostgreSQL database endpoint (on EC2)"
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
  value       = try(module.logging[0].loki_endpoint, null)
  description = "Loki log aggregation endpoint"
}

output "grafana_admin_user" {
  value       = try(module.logging[0].grafana_admin_user, null)
  description = "Grafana admin username"
}

output "grafana_admin_password" {
  value       = try(module.logging[0].grafana_admin_password, null)
  sensitive   = true
  description = "Grafana admin password (sensitive)"
}

output "kubeconfig_path" {
  value       = local.kubeconfig_path
  description = "Local kubeconfig path used by kubernetes and helm providers"
}

output "waf_web_acl_arn" {
  value       = module.waf.web_acl_arn
  description = "WAF Web ACL ARN for the portal"
}

output "waf_web_acl_name" {
  value       = module.waf.web_acl_name
  description = "WAF Web ACL name for the portal"
}

output "swarm_manager_ips" {
  value       = try(module.docker_swarm[0].swarm_manager_ips, [])
  description = "Public IPs of Docker Swarm manager nodes (if enabled)"
}

output "swarm_worker_ips" {
  value       = try(module.docker_swarm[0].swarm_worker_ips, [])
  description = "Public IPs of Docker Swarm worker nodes (if enabled)"
}

output "swarm_security_group_id" {
  value       = try(module.docker_swarm[0].swarm_security_group_id, null)
  description = "Security group ID for Docker Swarm cluster (if enabled)"
}
