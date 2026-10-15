terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }

  # Remote state in S3 (created by bootstrap/). use_lockfile = native S3 locking.
  backend "s3" {
    # bucket is passed at init time:  terraform init -backend-config="bucket=<name>"
    key          = "dev/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Environment = "dev", Project = "CloudNative-Mesh" }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name         = "cnm-dev"
  cluster_name = "cnm-dev-eks"
  azs          = slice(data.aws_availability_zones.available.names, 0, 2)
}

# ---------------- STEP 1: network ----------------
module "vpc" {
  source = "../../modules/vpc"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  azs                = local.azs
  single_nat_gateway = true # dev: save money. Set false in prod.
  cluster_name       = local.cluster_name
}

# ---------------- STEP 3: Kubernetes ----------------
module "eks" {
  source = "../../modules/eks"

  cluster_name                 = local.cluster_name
  vpc_id                       = module.vpc.vpc_id
  private_subnet_ids           = module.vpc.private_subnet_ids
  endpoint_public_access_cidrs = var.cluster_public_access_cidrs
}

# ---------------- STEP 2: data layer ----------------
# Step 3 upgrade: instead of trusting whole subnets (CIDRs), trust only the
# EKS security group. Only pods/nodes in the cluster can reach the data tier.
module "rds" {
  source = "../../modules/rds"

  name            = local.name
  vpc_id          = module.vpc.vpc_id
  data_subnet_ids = module.vpc.data_subnet_ids

  allowed_security_group_ids = [module.eks.cluster_security_group_id]
}

module "redis" {
  source = "../../modules/redis"

  name            = local.name
  vpc_id          = module.vpc.vpc_id
  data_subnet_ids = module.vpc.data_subnet_ids

  allowed_security_group_ids = [module.eks.cluster_security_group_id]
}


# ---------------- STEP 4b: IAM role for the API pods (IRSA) ----------------
module "api_irsa" {
  source = "../../modules/irsa"

  name              = "${local.name}-api"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  namespace         = "app"
  service_account   = "api"
  secret_arns       = [module.rds.master_secret_arn]
}
