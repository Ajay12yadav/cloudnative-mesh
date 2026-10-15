variable "name" {
  description = "IAM role name for GitHub Actions"
  type        = string
}

variable "github_repo" {
  description = "owner/repo that may assume the role, e.g. Ajay12yadav/cloudnative-mesh"
  type        = string
}

variable "branch" {
  description = "Only workflows running on this branch may assume the role"
  type        = string
  default     = "main"
}

variable "ecr_repository_arns" {
  description = "ECR repositories the role may push to"
  type        = list(string)
}

variable "create_oidc_provider" {
  description = "false if this AWS account already has the GitHub OIDC provider (only one per account)"
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
