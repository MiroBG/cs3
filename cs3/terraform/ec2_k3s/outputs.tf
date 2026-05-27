output "instance_id" {
  value       = try(aws_instance.k3s[0].id, null)
  description = "EC2 instance ID (null if instance not created)"
}

output "instance_public_ip" {
  value       = try(aws_eip.k3s[0].public_ip, null)
  description = "Public Elastic IP address (null if not created)"
}

output "instance_private_ip" {
  value       = try(aws_instance.k3s[0].private_ip, null)
  description = "Private IP address (null if instance not created)"
}

output "security_group_id" {
  value       = aws_security_group.k3s.id
  description = "Security group ID"
}

output "kubernetes_endpoint" {
  value       = try("https://${aws_eip.k3s[0].public_ip}:6443", null)
  description = "k3s API endpoint (null if not created)"
}

output "grafana_endpoint" {
  value       = try("http://${aws_eip.k3s[0].public_ip}:30100", null)
  description = "Grafana URL (null if not created)"
}

output "postgresql_endpoint" {
  value       = try("${aws_instance.k3s[0].private_ip}:5432", null)
  description = "PostgreSQL endpoint (null if instance not created)"
}

output "kubeconfig_path" {
  value       = "/opt/k3s/kubeconfig.yaml"
  description = "Path to kubeconfig on the instance"
}
