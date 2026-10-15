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

  name                 = "cnm-dev" # keeps the repository names cnm-dev/api and cnm-dev/frontend
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

############################################################
# COST GUARDRAILS (7c): email alerts before a forgotten cluster hurts
# Budget data lags real usage by several hours, so treat these as a safety net,
# not a real-time meter. The real protection is running scripts/down.sh.
############################################################
resource "aws_budgets_budget" "monthly" {
  name         = "cnm-monthly-cost"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED" # warns BEFORE you actually overspend
    subscriber_email_addresses = [var.alert_email]
  }
}

# A daily budget catches "I forgot to destroy the cluster" within a day or so
resource "aws_budgets_budget" "daily" {
  name         = "cnm-daily-cost"
  budget_type  = "COST"
  limit_amount = tostring(var.daily_budget_usd)
  limit_unit   = "USD"
  time_unit    = "DAILY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}
