############################################################
# EKS MODULE
#   1. IAM role for the control plane
#   2. The cluster (control plane run by AWS)
#   3. OIDC provider  (lets pods assume IAM roles: IRSA)
#   4. IAM role for worker nodes
#   5. Managed node group (EC2 workers in private subnets)
#   6. Add-ons (networking, DNS, EBS storage driver)
############################################################

locals {
  tags     = merge(var.tags, { Project = "CloudNative-Mesh", ManagedBy = "Terraform" })
  oidc_url = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

# ---------- 1. Control plane IAM role ----------
data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"] # only the EKS service may use this role
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------- 2. The cluster ----------
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true # nodes talk to the API privately, inside the VPC
    endpoint_public_access  = true # so kubectl works from your laptop
    public_access_cidrs     = var.endpoint_public_access_cidrs
  }

  # Modern auth: "access entries" managed through the AWS API,
  # instead of editing the old aws-auth ConfigMap by hand.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true # whoever runs terraform becomes admin
  }

  tags = merge(local.tags, { Name = var.cluster_name })

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# ---------- 3. OIDC provider (IRSA) ----------
# Kubernetes issues signed tokens to pods. Registering the cluster's issuer
# with IAM lets AWS trust those tokens and hand a pod a specific IAM role.
resource "aws_iam_openid_connect_provider" "this" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
  tags           = local.tags
}

# ---------- 4. Worker node IAM role ----------
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",          # join the cluster
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",                # manage pod IPs/ENIs
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly", # pull images from ECR
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",       # shell access without SSH
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# ---------- 5. Managed node group ----------
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.node_instance_types
  capacity_type  = "ON_DEMAND"
  ami_type       = "AL2023_x86_64_STANDARD"
  disk_size      = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1 # rolling upgrades: one node at a time
  }

  tags = merge(local.tags, { Name = "${var.cluster_name}-node" })

  depends_on = [aws_iam_role_policy_attachment.node]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size] # let autoscaling change it later
  }
}

# ---------- 6. Add-ons ----------
# These two do not need nodes to exist first.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  tags                        = local.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  tags                        = local.tags
}

# CoreDNS runs as pods, so it needs worker nodes first.
resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  tags                        = local.tags
  depends_on                  = [aws_eks_node_group.this]
}

# EBS CSI driver: needs its OWN IAM role (IRSA) to create/attach EBS volumes.
data "aws_iam_policy_document" "ebs_csi_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub" # only THIS service account...
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = aws_iam_role.ebs_csi.arn
  resolve_conflicts_on_create = "OVERWRITE"
  tags                        = local.tags
  depends_on                  = [aws_eks_node_group.this, aws_iam_role_policy_attachment.ebs_csi]
}
