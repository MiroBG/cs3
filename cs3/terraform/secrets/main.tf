resource "aws_secretsmanager_secret" "db_password" {
  name                    = "cs3/db_password"
  description             = "Database password for CS3 employees database"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_password_version" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    password = var.db_password
  })
}

output "db_secret_arn" {
  value = aws_secretsmanager_secret.db_password.arn
}
