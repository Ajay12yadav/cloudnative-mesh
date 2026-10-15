variable "name" {
  description = "Prefix for repository names, e.g. cnm-dev -> cnm-dev/api"
  type        = string
}

variable "repositories" {
  description = "Repositories to create (one per container image)"
  type        = list(string)
  default     = ["api", "frontend"]
}

variable "image_tag_mutability" {
  description = "MUTABLE lets you re-push the same tag (handy in dev). IMMUTABLE is safer for prod."
  type        = string
  default     = "MUTABLE"
}

variable "force_delete" {
  description = "true = terraform destroy deletes the repo even if it still holds images (dev)"
  type        = bool
  default     = true
}

variable "keep_last" {
  description = "Lifecycle policy: how many images to keep per repository"
  type        = number
  default     = 10
}

variable "tags" {
  type    = map(string)
  default = {}
}
