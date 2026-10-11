############################################################
# REDIS MODULE: ElastiCache replication group in the data subnets
############################################################

locals {
  ha   = var.num_cache_clusters > 1
  tags = merge(var.tags, { Project = "CloudNative-Mesh", ManagedBy = "Terraform" })
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name}-redis-subnets"
  subnet_ids = var.data_subnet_ids
  tags       = local.tags
}

resource "aws_security_group" "this" {
  name        = "${var.name}-redis-sg"
  description = "Redis access for application workloads only"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${var.name}-redis-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "from_cidr" {
  count             = length(var.allowed_cidr_blocks)
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = var.allowed_cidr_blocks[count.index]
  from_port         = 6379
  to_port           = 6379
  ip_protocol       = "tcp"
  description       = "Redis from app subnet"
}

resource "aws_vpc_security_group_ingress_rule" "from_sg" {
  count                        = length(var.allowed_security_group_ids)
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  description                  = "Redis from app security group"
}

# A replication group (not a bare cluster) is what supports encryption
# in transit, replicas and automatic failover.
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name}-redis"
  description          = "Redis cache for ${var.name}"

  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = 6379
  parameter_group_name = "default.redis7"

  num_cache_clusters         = var.num_cache_clusters
  automatic_failover_enabled = local.ha
  multi_az_enabled           = local.ha

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true # clients must connect with TLS (rediss://)

  snapshot_retention_limit = 0 # no backups for a cache in dev
  apply_immediately        = true

  tags = merge(local.tags, { Name = "${var.name}-redis" })
}
