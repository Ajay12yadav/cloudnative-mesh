variable "name" {
  description = "Prefix for resource names, e.g. cnm-dev"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "data_subnet_ids" {
  description = "Isolated data subnets (one per AZ)"
  type        = list(string)
}

variable "allowed_cidr_blocks" {
  description = "CIDRs allowed to reach Redis on 6379 (Step 2: private subnet CIDRs)"
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to reach Redis (Step 3: the EKS SG)"
  type        = list(string)
  default     = []
}

variable "engine_version" {
  type    = string
  default = "7.1"
}

variable "node_type" {
  description = "Cache node size"
  type        = string
  default     = "cache.t4g.micro"
}

variable "num_cache_clusters" {
  description = "Number of nodes: 1 = primary only (dev). 2+ = primary plus replicas with automatic failover (prod)."
  type        = number
  default     = 1
}

variable "tags" {
  type    = map(string)
  default = {}
}
