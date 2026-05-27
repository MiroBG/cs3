variable "logging_namespace" {
  type    = string
  default = "logging"
}

variable "grafana_admin_password" {
  type        = string
  sensitive   = true
  description = "Grafana admin password"
}

variable "loki_stack_chart_version" {
  type        = string
  default     = "2.10.3"
  description = "Pinned grafana/loki-stack chart version. 2.10.3 is the newest loki-stack version currently published in the Grafana Helm repo."
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
