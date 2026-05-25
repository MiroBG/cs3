terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.28"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

locals {
  resource_suffix_part = var.resource_suffix != "" ? "-${var.resource_suffix}" : ""
  eks_cluster_name     = "${var.cluster_name}${local.resource_suffix_part}"
  kubernetes_ready     = var.kubernetes_host != "" && var.kubernetes_cluster_ca_certificate != ""
}

provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = local.kubernetes_ready ? var.kubernetes_host : "https://127.0.0.1"
  cluster_ca_certificate = local.kubernetes_ready ? base64decode(var.kubernetes_cluster_ca_certificate) : ""
  token                  = local.kubernetes_ready ? data.aws_eks_cluster_auth.this[0].token : ""
}

data "aws_eks_cluster_auth" "this" {
  count = local.kubernetes_ready ? 1 : 0
  name  = local.eks_cluster_name
}

provider "helm" {
  kubernetes {
    host                   = local.kubernetes_ready ? var.kubernetes_host : "https://127.0.0.1"
    cluster_ca_certificate = local.kubernetes_ready ? base64decode(var.kubernetes_cluster_ca_certificate) : ""
    token                  = local.kubernetes_ready ? data.aws_eks_cluster_auth.this[0].token : ""
  }
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

module "eks" {
  source = "./eks"

  cluster_name                    = var.cluster_name
  vpc_id                          = module.vpc.vpc_id
  vpc_cidr                        = var.vpc_cidr
  subnet_ids                      = var.use_default_vpc ? module.vpc.public_subnet_ids : module.vpc.private_subnet_ids
  kubernetes_version              = var.kubernetes_version
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = var.cluster_endpoint_private_access
  capacity_type                   = var.capacity_type
  node_instance_types             = var.node_instance_types
  desired_size                    = var.desired_size
  min_size                        = var.min_size
  max_size                        = var.max_size
  resource_suffix                 = var.resource_suffix
  tags                            = var.tags
}

module "rds" {
  source = "./rds"

  vpc_id               = module.vpc.vpc_id
  vpc_cidr             = var.vpc_cidr
  database_subnet_ids  = module.vpc.database_subnet_ids
  db_name              = "${var.name_prefix}-employee-db${local.resource_suffix_part}"
  resource_suffix      = var.resource_suffix
  db_database_name     = "employees"
  db_username          = var.db_username
  db_password          = var.db_password
  db_instance_class    = var.db_instance_class
  db_allocated_storage = var.db_allocated_storage
  db_multi_az          = var.db_multi_az
  tags                 = var.tags
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
  count  = local.kubernetes_ready ? 1 : 0
  source = "./logging"

  logging_namespace      = var.logging_namespace
  grafana_admin_password = var.grafana_admin_password
  resource_suffix        = var.resource_suffix
  tags                   = var.tags

  depends_on = [module.eks]
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
