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
  }
}

provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.this.token
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
  enable_nat_gateway    = var.enable_nat_gateway
  tags                  = var.tags
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

module "rds" {
  source = "./rds"

  vpc_id               = module.vpc.vpc_id
  vpc_cidr             = var.vpc_cidr
  database_subnet_ids  = module.vpc.database_subnet_ids
  db_name              = "${var.name_prefix}-employee-db"
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
  identity_pool_name               = "${var.name_prefix}-identity-pool"
  allow_unauthenticated_identities = false

  supported_login_providers = {
    "cognito-idp.${var.region}.amazonaws.com/${module.cognito.user_pool_id}:${module.cognito.client_id}" = "cs3-portal"
  }

  tags = var.tags
}

module "cognito" {
  source = "./cognito"

  user_pool_name       = "${var.name_prefix}-employees"
  cognito_domain       = var.cognito_domain
  aws_region           = var.region
  callback_urls        = var.cognito_callback_urls
  logout_urls          = var.cognito_logout_urls
  identity_pool_id     = aws_cognito_identity_pool.this.id
  employee_bucket_name = var.employee_bucket_name
  tags                 = var.tags
}

module "ecr" {
  source = "./ecr"

  name_prefix  = var.name_prefix
  cluster_name = var.cluster_name
  tags         = var.tags
}

module "logging" {
  source = "./logging"

  logging_namespace      = var.logging_namespace
  grafana_admin_password = var.grafana_admin_password
  tags                   = var.tags

  depends_on = [module.eks]
}
