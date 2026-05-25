terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

locals {
  resource_suffix_part = var.resource_suffix != "" ? "-${var.resource_suffix}" : ""
}

provider "aws" {
  region = var.region
}

module "vpc" {
  source = "./vpc"

  name_prefix           = var.name_prefix
  cluster_name          = var.cluster_name
  vpc_cidr              = var.vpc_cidr
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  azs                   = var.azs
  enable_nat_gateway    = var.enable_nat_gateway && !var.use_default_vpc
  tags                  = var.tags
}

module "ec2_k3s" {
  source = "./ec2_k3s"

  name_prefix            = var.name_prefix
  resource_suffix_part   = local.resource_suffix_part
  instance_type          = var.ec2_instance_type
  root_volume_size       = var.ec2_root_volume_size
  vpc_id                 = module.vpc.vpc_id
  subnet_id              = module.vpc.public_subnet_ids[0]
  vpc_cidr               = var.vpc_cidr
  db_password            = var.db_password
  grafana_admin_password = var.grafana_admin_password
  tags                   = var.tags
}

# Cognito Identity Pool for federated access
resource "aws_cognito_identity_pool" "this" {
  identity_pool_name               = "${var.name_prefix}-identity-pool${local.resource_suffix_part}"
  allow_unauthenticated_identities = false

  supported_login_providers = {
    "cognito-idp.${var.region}.amazonaws.com/${module.cognito.user_pool_id}:${module.cognito.client_id}" = "cs3-portal"
  }

  tags = var.tags
}

module "cognito" {
  source = "./cognito"

  user_pool_name        = "${var.name_prefix}-employees${local.resource_suffix_part}"
  cognito_domain        = var.cognito_domain
  aws_region            = var.region
  callback_urls         = var.cognito_callback_urls
  logout_urls           = var.cognito_logout_urls
  identity_pool_id      = aws_cognito_identity_pool.this.id
  employee_bucket_name  = var.employee_bucket_name
  tags                  = var.tags
  manage_cognito_domain = var.manage_cognito_domain
}

module "ecr" {
  source = "./ecr"

  name_prefix     = var.name_prefix
  cluster_name    = var.cluster_name
  resource_suffix = var.resource_suffix
  tags            = var.tags
}

module "logging" {
  count  = 1 # Always deploy logging since we have k3s
  source = "./logging"

  logging_namespace      = var.logging_namespace
  grafana_admin_password = var.grafana_admin_password
  resource_suffix        = var.resource_suffix
  tags                   = var.tags

  depends_on = [module.ec2_k3s]
}

module "waf" {
  source = "./waf"

  name_prefix        = var.name_prefix
  rate_limit         = var.waf_rate_limit
  portal_alb_arn     = var.portal_alb_arn
  enable_association = var.enable_waf_association
  resource_suffix    = var.resource_suffix
  tags               = var.tags
}

module "docker_swarm" {
  count  = var.enable_docker_swarm ? 1 : 0
  source = "./docker_swarm"

  swarm_manager_count = var.swarm_manager_count
  swarm_worker_count  = var.swarm_worker_count
  instance_type       = var.swarm_instance_type
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.public_subnet_ids
  key_name            = var.swarm_key_name
  tags                = var.tags
}
