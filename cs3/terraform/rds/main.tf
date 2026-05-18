resource "aws_db_subnet_group" "this" {
  name       = "${var.db_name}-subnet-group"
  subnet_ids = var.database_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.db_name}-subnet-group"
  })
}

resource "aws_security_group" "rds" {
  name        = "${var.db_name}-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL from VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.db_name}-sg"
  })
}

resource "aws_db_instance" "this" {
  identifier     = var.db_name
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  db_name  = var.db_database_name
  username = var.db_username
  password = var.db_password

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az                = var.db_multi_az
  backup_retention_period = var.db_backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  skip_final_snapshot       = var.db_skip_final_snapshot
  final_snapshot_identifier = "${var.db_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  tags = merge(var.tags, {
    Name = "${var.db_name}-instance"
  })
}

resource "aws_db_instance" "read_replica" {
  count               = var.create_read_replica ? 1 : 0
  identifier          = "${var.db_name}-read-replica"
  replicate_source_db = aws_db_instance.this.identifier
  instance_class      = var.db_instance_class
  skip_final_snapshot = true

  tags = merge(var.tags, {
    Name = "${var.db_name}-read-replica"
  })
}

output "rds_endpoint" {
  value       = aws_db_instance.this.endpoint
  description = "RDS instance endpoint (hostname:port)"
}

output "rds_database_name" {
  value = aws_db_instance.this.db_name
}

output "rds_master_username" {
  value     = aws_db_instance.this.username
  sensitive = true
}

output "rds_security_group_id" {
  value = aws_security_group.rds.id
}
