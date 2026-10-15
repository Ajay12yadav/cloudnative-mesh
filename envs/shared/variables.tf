variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "github_repo" {
  description = "How GitHub names this repo inside its OIDC token: owner@ownerID/repo@repoID. Find yours by running a workflow that prints the 'sub' claim."
  type        = string
  default     = "Ajay12yadav@170036543/cloudnative-mesh@1413134438"
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

variable "alert_email" {
  description = "Email address that receives AWS Budget alerts"
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be a valid email address."
  }
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget in USD. Adjust after you see your real bills."
  type        = number
  default     = 40
}

variable "daily_budget_usd" {
  description = "Daily cost budget in USD. A day with the whole platform running should stay below this."
  type        = number
  default     = 12
}
