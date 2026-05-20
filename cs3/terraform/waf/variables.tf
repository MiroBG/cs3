variable "name_prefix" {
  type    = string
  default = "cs3"
}

variable "resource_suffix" {
  type        = string
  default     = "v2"
  description = "Suffix appended to resource names to avoid collisions"
}

variable "rate_limit" {
  type        = number
  default     = 2000
  description = "Requests per 5-minute window per IP before blocking"
}

variable "portal_alb_arn" {
  type        = string
  default     = null
  description = "Optional ALB ARN to associate with the web ACL"
}

variable "enable_association" {
  type        = bool
  default     = false
  description = "Set true when an ALB ARN is available for association"
}

variable "tags" {
  type    = map(string)
  default = {}
}