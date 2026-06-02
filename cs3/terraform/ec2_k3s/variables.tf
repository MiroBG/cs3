variable "name_prefix" {
  type        = string
  description = "Prefix for resource names"
}

variable "resource_suffix_part" {
  type        = string
  description = "Resource suffix (e.g., '-v6')"
  default     = ""
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type"
}

variable "create_instance" {
  type        = bool
  default     = true
  description = "Whether to create the EC2 instance (set false to skip when quotas are low)"
}

variable "root_volume_size" {
  type        = number
  default     = 30
  description = "Root volume size in GB"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where instance will be launched"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID where instance will be launched"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR for security group"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "PostgreSQL database password"
}

variable "grafana_admin_password" {
  type        = string
  sensitive   = true
  description = "Grafana admin password"
}

variable "kubeconfig_parameter_name" {
  type        = string
  default     = "/cs3/k3s/kubeconfig"
  description = "SSM Parameter Store name where the EC2 bootstrap publishes kubeconfig"
}

variable "cognito_user_pool_arn" {
  type        = string
  default     = "*"
  description = "Cognito User Pool ARN used by the portal for admin provisioning"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to resources"
}
