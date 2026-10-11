output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_security_group_id" {
  description = "SG that EKS attaches to the nodes. RDS and Redis trust this one."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "Used later to create IAM roles for service accounts (IRSA)"
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  value = local.oidc_url
}

output "node_role_arn" {
  value = aws_iam_role.node.arn
}
