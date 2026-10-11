variable "name" {
  description = "IAM role name, e.g. cnm-dev-api"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider (output of the eks module)"
  type        = string
}

variable "oidc_provider_url" {
  description = "Issuer URL without https:// (output of the eks module)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the service account"
  type        = string
}

variable "service_account" {
  description = "Kubernetes service account name allowed to assume this role"
  type        = string
}

variable "secret_arns" {
  description = "Secrets Manager secrets this role may read"
  type        = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
