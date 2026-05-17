variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "name_prefix" {
  type    = string
  default = "cs3"
}

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.30.0.0/24", "10.30.1.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.30.10.0/24", "10.30.11.0/24"]
}

variable "azs" {
  type    = list(string)
  default = ["eu-central-1a", "eu-central-1b"]
}

variable "enable_nat_gateway" {
  type    = bool
  default = true
}

variable "cluster_name" {
  type    = string
  default = "cs3-eks-cluster"
}

variable "kubernetes_version" {
  type    = string
  default = "1.30"
}

variable "cluster_endpoint_public_access" {
  type    = bool
  default = true
}

variable "cluster_endpoint_private_access" {
  type    = bool
  default = false
}

variable "capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.small"]
}

variable "desired_size" {
  type    = number
  default = 1
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 2
}

variable "tags" {
  type    = map(string)
  default = {}
}
