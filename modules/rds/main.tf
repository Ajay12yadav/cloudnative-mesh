############################################################
# RDS MODULE: managed PostgreSQL inside the isolated data subnets
############################################################

locals {
  # "16" or "16.4" -> "postgres16" (parameter group family)
  pg_family = "postgres${split(".", var.engine_version)[0]}"
  tags      = merge(var.tags, { Project = "CloudNative-Mesh", ManagedBy = "Terraform" })
}

# ---------- Subnet group: tells RDS WHICH subnets it may use ----------
resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.data_subnet_ids # must cover at least 2 AZs
  tags       = merge(local.tags, { Name = "${var.name}-db-subnets" })
}

# ---------- Security group: who may talk to the database ----------
resource "aws_security_group" "this" {
  name        = "${var.name}-rds-sg"
  description = "PostgreSQL access for application workloads only"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${var.name}-rds-sg" })
  # No inline rules and no egress: Terraform removes AWS's default allow-all
  # egress. SGs are stateful, so replies to allowed requests still flow.
}

resource "aws_vpc_security_group_ingress_rule" "from_cidr" {
  count             = length(var.allowed_cidr_blocks)
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = var.allowed_cidr_blocks[count.index]
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  description       = "Postgres from app subnet"
}

resource "aws_vpc_security_group_ingress_rule" "from_sg" {
  count                        = length(var.allowed_security_group_ids)
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Postgres from app security group"
}

# ---------- Parameter group: engine settings ----------
resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-pg-"
  family      = local.pg_family
  description = "Postgres settings for ${var.name}"

  parameter {
    name  = "rds.force_ssl" # reject unencrypted client connections
    value = "1"
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true # a group in use cannot be deleted first
  }
}

# ---------- The database instance ----------
resource "aws_db_instance" "this" {
  identifier     = "${var.name}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true # AWS-managed KMS key

  # Initial database + admin user.
  # RDS generates the password and stores it in Secrets Manager, so it
  # never appears in your code or in the Terraform state.
  db_name                     = var.db_name
  username                    = var.master_username
  manage_master_user_password = true

  # Network: isolated subnets, no public address
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  multi_az               = var.multi_az
  parameter_group_name   = aws_db_parameter_group.this.name

  # Backups and lifecycle
  backup_retention_period    = var.backup_retention_days
  auto_minor_version_upgrade = true
  skip_final_snapshot        = var.skip_final_snapshot
  final_snapshot_identifier  = var.skip_final_snapshot ? null : "${var.name}-postgres-final"
  deletion_protection        = var.deletion_protection
  apply_immediately          = true

  tags = merge(local.tags, { Name = "${var.name}-postgres" })

  lifecycle {
    ignore_changes = [engine_version] # AWS auto-upgrades minors; don't fight it
  }
}
