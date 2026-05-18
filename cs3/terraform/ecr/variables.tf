variable "name_prefix" {
  type    = string
  default = "cs3"
}

variable "cluster_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
