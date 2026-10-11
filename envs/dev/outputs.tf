# ----- Step 1 -----
output "vpc_id" { value = module.vpc.vpc_id }
output "public_subnet_ids" { value = module.vpc.public_subnet_ids }
output "private_subnet_ids" { value = module.vpc.private_subnet_ids }
output "data_subnet_ids" { value = module.vpc.data_subnet_ids }
output "nat_public_ips" { value = module.vpc.nat_public_ips }

# ----- Step 2 -----
output "rds_address" { value = module.rds.address }
output "rds_port" { value = module.rds.port }
output "rds_db_name" { value = module.rds.db_name }
output "rds_master_secret_arn" { value = module.rds.master_secret_arn }
output "redis_primary_endpoint" { value = module.redis.primary_endpoint }

# ----- Step 3 -----
output "eks_cluster_name" { value = module.eks.cluster_name }
output "eks_cluster_endpoint" { value = module.eks.cluster_endpoint }
output "eks_cluster_security_group_id" { value = module.eks.cluster_security_group_id }
output "eks_oidc_provider_arn" { value = module.eks.oidc_provider_arn }
output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
