variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "name_prefix" {
  type    = string
  default = "cs3"
}

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.30.0.0/24", "10.30.1.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.30.10.0/24", "10.30.11.0/24"]
}

variable "database_subnet_cidrs" {
  type    = list(string)
  default = ["10.30.20.0/24", "10.30.21.0/24"]
}

variable "azs" {
  type    = list(string)
  default = ["eu-central-1a", "eu-central-1b"]
}

variable "enable_nat_gateway" {
  type    = bool
  default = true
}

variable "use_default_vpc" {
  type        = bool
  default     = true
  description = "Reuse the AWS account default VPC instead of creating a new one"
}

variable "resource_suffix" {
  type        = string
  default     = "v2"
  description = "Suffix appended to resource names to avoid collisions"
}

variable "cluster_name" {
  type    = string
  default = "cs3-eks-cluster"
}

variable "kubernetes_version" {
  type    = string
  default = "1.30"
}

variable "cluster_endpoint_public_access" {
  type    = bool
  default = true
}

variable "cluster_endpoint_private_access" {
  type    = bool
  default = false
}

variable "capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.small"]
}

variable "desired_size" {
  type    = number
  default = 1
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 2
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "RDS master password for employee database"
}

variable "db_username" {
  type        = string
  default     = "admin"
  description = "RDS master username"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "cognito_domain" {
  type        = string
  description = "Cognito domain name (must be globally unique)"
  default     = "cs3-employees-prod"
}

variable "cognito_callback_urls" {
  type        = list(string)
  description = "OAuth callback URLs for the Cognito app client"
  default     = ["http://localhost:3000/callback", "https://portal.innovatech.local/callback"]
}

variable "cognito_logout_urls" {
  type        = list(string)
  description = "OAuth logout URLs"
  default     = ["http://localhost:3000/logout", "https://portal.innovatech.local/logout"]
}

variable "employee_bucket_name" {
  type        = string
  description = "S3 bucket for employee documents"
  default     = "cs3-employee-docs"
}

variable "logging_namespace" {
  type        = string
  description = "Kubernetes namespace for logging infrastructure"
  default     = "logging"
}

variable "grafana_admin_password" {
  type        = string
  sensitive   = true
  description = "Grafana admin password for Loki visualization"
}

variable "portal_alb_arn" {
  type        = string
  default     = null
  description = "Optional ALB ARN for WAF association"
}

variable "enable_waf_association" {
  type        = bool
  default     = false
  description = "Enable WAF association when an ALB ARN is available"
}

variable "waf_rate_limit" {
  type        = number
  default     = 2000
  description = "Rate limit threshold for WAF per IP"
}

variable "enable_docker_swarm" {
  type        = bool
  default     = false
  description = "Enable Docker Swarm cluster for orchestration comparison (research only)"
}

variable "swarm_manager_count" {
  type        = number
  default     = 3
  description = "Number of Docker Swarm manager nodes (if enabled)"
}

variable "swarm_worker_count" {
  type        = number
  default     = 3
  description = "Number of Docker Swarm worker nodes (if enabled)"
}

variable "swarm_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type for Swarm nodes"
}

variable "swarm_key_name" {
  type        = string
  default     = ""
  description = "EC2 key pair name for Swarm node SSH access"
}

variable "tags" {
  type    = map(string)
  default = {}
}
