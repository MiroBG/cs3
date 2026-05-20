variable "logging_namespace" {
  type    = string
  default = "logging"
}

variable "grafana_admin_password" {
  type        = string
  sensitive   = true
  description = "Grafana admin password"
}

variable "resource_suffix" {
  type        = string
  default     = "v2"
  description = "Suffix appended to resource names to avoid collisions"
}

variable "tags" {
  type    = map(string)
  default = {}
}
