variable "db_password" {
  type        = string
  sensitive   = true
  description = "Database password to store in AWS Secrets Manager"
}
