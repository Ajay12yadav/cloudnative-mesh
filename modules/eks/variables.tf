variable "cluster_name" {
  description = "EKS cluster name (must match the subnet tags set in the vpc module)"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes minor version. Check: aws eks describe-cluster-versions"
  type        = string
  default     = "1.34"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Private subnets: the control-plane network interfaces and worker nodes live here"
  type        = list(string)
}

variable "endpoint_public_access_cidrs" {
  description = "Who may reach the PUBLIC Kubernetes API endpoint. Restrict to your IP, e.g. [\"1.2.3.4/32\"]"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "node_disk_size" {
  description = "Root disk size per node in GiB"
  type        = number
  default     = 20
}

variable "tags" {
  type    = map(string)
  default = {}
}
