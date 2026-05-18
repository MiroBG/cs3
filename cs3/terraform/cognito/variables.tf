variable "user_pool_name" {
  type    = string
  default = "cs3-employees"
}

variable "cognito_domain" {
  type        = string
  description = "Cognito domain name (must be globally unique)"
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "callback_urls" {
  type    = list(string)
  default = ["http://localhost:3000/callback", "https://portal.innovatech.local/callback"]
}

variable "logout_urls" {
  type    = list(string)
  default = ["http://localhost:3000/logout", "https://portal.innovatech.local/logout"]
}

variable "enable_google_provider" {
  type    = bool
  default = false
}

variable "google_client_id" {
  type      = string
  default   = ""
  sensitive = true
}

variable "google_client_secret" {
  type      = string
  default   = ""
  sensitive = true
}

variable "identity_pool_id" {
  type        = string
  description = "Cognito Identity Pool ID for federated access"
}

variable "employee_bucket_name" {
  type        = string
  description = "S3 bucket for employee documents"
}

variable "tags" {
  type    = map(string)
  default = {}
}
