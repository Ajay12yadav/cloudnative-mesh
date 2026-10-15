############################################################
# SHARED LAYER: things that must SURVIVE daily teardowns
#   - ECR repositories (container images)
#   - GitHub Actions -> AWS trust (OIDC provider + CI role)
# Costs pennies per month. Never destroyed by scripts/down.sh.
############################################################
terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }

  backend "s3" {
    # bucket passed at init time: terraform init -backend-config="bucket=<name>"
    key          = "shared/terraform.tfstate" # its OWN state file, separate from dev
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Environment = "shared", Project = "CloudNative-Mesh" }
  }
}

module "ecr" {
  source = "../../modules/ecr"

  name                 = "cnm-dev"   # keeps the repository names cnm-dev/api and cnm-dev/frontend
  image_tag_mutability = "IMMUTABLE" # a tag (the Git commit SHA) can never be overwritten
  force_delete         = false       # refuse to delete a repository that still holds images
  keep_last            = 30
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  name                 = "cnm-github-ci"
  github_repo          = var.github_repo
  branch               = var.github_branch
  ecr_repository_arns  = values(module.ecr.repository_arns)
  create_oidc_provider = var.create_oidc_provider
}
