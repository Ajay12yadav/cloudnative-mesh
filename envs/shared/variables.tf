variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "github_repo" {
  description = "owner/repo allowed to push images"
  type        = string
  default     = "Ajay12yadav/cloudnative-mesh"
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "create_oidc_provider" {
  description = "Set false if the account already has a GitHub OIDC provider"
  type        = bool
  default     = true
}
