variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "cluster_public_access_cidrs" {
  description = "Who can reach the public Kubernetes API. Set to [\"<your-ip>/32\"] for safety."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
