terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

module "vpc" {
  source = "./vpc"

  name_prefix          = var.name_prefix
  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  azs                  = var.azs
  enable_nat_gateway   = var.enable_nat_gateway
  tags                 = var.tags
}

module "eks" {
  source = "./eks"

  cluster_name                    = var.cluster_name
  vpc_id                          = module.vpc.vpc_id
  vpc_cidr                        = var.vpc_cidr
  subnet_ids                      = module.vpc.private_subnet_ids
  kubernetes_version              = var.kubernetes_version
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = var.cluster_endpoint_private_access
  capacity_type                   = var.capacity_type
  node_instance_types             = var.node_instance_types
  desired_size                    = var.desired_size
  min_size                        = var.min_size
  max_size                        = var.max_size
  tags                            = var.tags
}
