variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "state_bucket" {
  description = "S3 bucket holding the Terraform state (to read the outputs of envs/dev)"
  type        = string
  default     = "terraform-bucket-ajay-2026-xyz"
}

variable "argocd_chart_version" {
  description = "argo/argo-cd chart version. Empty = newest; pin it after the first install."
  type        = string
  default     = ""
}
