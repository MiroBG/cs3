variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "database_subnet_ids" {
  type = list(string)
}

variable "db_name" {
  type    = string
  default = "cs3-employee-db"
}

variable "db_database_name" {
  type    = string
  default = "employees"
}

variable "db_username" {
  type      = string
  default   = "admin"
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_engine_version" {
  type    = string
  default = "15.4"
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

variable "db_backup_retention_days" {
  type    = number
  default = 7
}

variable "db_skip_final_snapshot" {
  type    = bool
  default = true
}

variable "create_read_replica" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
