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

module "vpc" {
  source = "../../modules/vpc"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  azs                = local.azs
  single_nat_gateway = true # dev: save money. Set false in prod.
  cluster_name       = local.cluster_name
}
