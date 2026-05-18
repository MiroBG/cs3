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

variable "tags" {
  type    = map(string)
  default = {}
}
