variable "name_prefix" {
  type    = string
  default = "cs3"
}

variable "cluster_name" {
  type = string
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
