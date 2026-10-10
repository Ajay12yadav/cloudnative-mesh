############################################################
# BOOTSTRAP: remote state bucket for Terraform
# Run ONCE with local state. Everything else stores its state here.
############################################################
terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "ap-south-1" # Mumbai: closest to you
}

variable "state_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name, e.g. cnm-tfstate-<yourname>-<random>"
}

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name
  lifecycle { prevent_destroy = true } # never delete state by accident
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" } # lets you roll back a bad state
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "state_bucket" { value = aws_s3_bucket.tfstate.id }
