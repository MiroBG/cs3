variable "logging_namespace" {
  type    = string
  default = "logging"
}

variable "grafana_admin_password" {
  type        = string
  sensitive   = true
  description = "Grafana admin password"
}

variable "tags" {
  type    = map(string)
  default = {}
}
