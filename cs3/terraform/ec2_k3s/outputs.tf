output "instance_id" {
  value       = aws_instance.k3s.id
  description = "EC2 instance ID"
}

output "instance_public_ip" {
  value       = aws_eip.k3s.public_ip
  description = "Public Elastic IP address"
}

output "instance_private_ip" {
  value       = aws_instance.k3s.private_ip
  description = "Private IP address"
}

output "security_group_id" {
  value       = aws_security_group.k3s.id
  description = "Security group ID"
}

output "kubernetes_endpoint" {
  value       = "https://${aws_eip.k3s.public_ip}:6443"
  description = "k3s API endpoint"
}

output "grafana_endpoint" {
  value       = "http://${aws_eip.k3s.public_ip}:30100"
  description = "Grafana URL"
}

output "postgresql_endpoint" {
  value       = "${aws_instance.k3s.private_ip}:5432"
  description = "PostgreSQL endpoint"
}

output "kubeconfig_path" {
  value       = "/opt/k3s/kubeconfig.yaml"
  description = "Path to kubeconfig on the instance"
}
