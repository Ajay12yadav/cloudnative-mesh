############################################################
# PLATFORM LAYER: what runs ON the cluster and bootstraps GitOps
#   - Argo CD (Helm)
#   - the Grafana admin Secret (random password)
#   - the "root" Application that hands everything else over to Git
#   - a destroy-time cleanup that removes load balancers and EBS volumes
#
# Needs the cluster to exist: apply envs/dev first.
# State is separate from envs/dev because these layers change at different speeds.
############################################################
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    helm       = { source = "hashicorp/helm", version = "~> 2.17" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.35" }
    kubectl    = { source = "gavinbunney/kubectl", version = "~> 1.14" }
    random     = { source = "hashicorp/random", version = "~> 3.6" }
  }

  backend "s3" {
    # bucket passed at init time: terraform init -backend-config="bucket=<name>"
    key          = "platform/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}

# Read the cluster details that envs/dev published as outputs
data "terraform_remote_state" "dev" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "dev/terraform.tfstate"
    region = var.region
  }
}

locals {
  dev          = data.terraform_remote_state.dev.outputs
  cluster_name = local.dev.eks_cluster_name
  endpoint     = local.dev.eks_cluster_endpoint
  ca           = base64decode(local.dev.eks_cluster_ca_data)

  # Short-lived credentials from the AWS CLI, no kubeconfig needed
  exec_args = ["eks", "get-token", "--cluster-name", local.cluster_name, "--region", var.region]
}

provider "kubernetes" {
  host                   = local.endpoint
  cluster_ca_certificate = local.ca
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.exec_args
  }
}

provider "helm" {
  kubernetes {
    host                   = local.endpoint
    cluster_ca_certificate = local.ca
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.exec_args
    }
  }
}

provider "kubectl" {
  host                   = local.endpoint
  cluster_ca_certificate = local.ca
  load_config_file       = false
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.exec_args
  }
}

# ---------------- Grafana admin secret ----------------
resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "random_password" "grafana" {
  length  = 20
  special = false
}

# Note: the password is also stored in the Terraform state (encrypted S3 bucket).
resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  data = {
    "admin-user"     = "admin"
    "admin-password" = random_password.grafana.result
  }
}

# ---------------- Argo CD ----------------
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version != "" ? var.argocd_chart_version : null

  values  = [file("${path.module}/../../gitops/bootstrap/argocd-values.yaml")]
  wait    = true
  timeout = 900
}

# Registers the NGINX OCI chart registry with Argo CD
resource "kubectl_manifest" "oci_repo" {
  yaml_body  = file("${path.module}/../../gitops/bootstrap/oci-repo-nginx.yaml")
  depends_on = [helm_release.argocd]
}

# The ONE Application: from here on, Git drives the cluster
resource "kubectl_manifest" "root_app" {
  yaml_body = file("${path.module}/../../gitops/bootstrap/root-app.yaml")
  depends_on = [
    helm_release.argocd,
    kubectl_manifest.oci_repo,
    kubernetes_secret_v1.grafana_admin,
  ]
}

# ---------------- Safe teardown ----------------
# Created LAST, so it is destroyed FIRST (while Argo CD still exists).
# It makes Argo delete everything it deployed, which removes the AWS load balancer
# and the EBS volumes that Kubernetes created and Terraform does not know about.
# If it fails, `terraform destroy` stops, and the VPC is NOT destroyed with a
# load balancer still attached.
resource "terraform_data" "cleanup_on_destroy" {
  input = {
    region  = var.region
    cluster = local.cluster_name
    vpc_id  = local.dev.vpc_id
    script  = abspath("${path.module}/../../scripts/platform-cleanup.sh")
  }

  provisioner "local-exec" {
    when    = destroy
    command = "bash ${self.input.script}"
    environment = {
      REGION  = self.input.region
      CLUSTER = self.input.cluster
      VPC_ID  = self.input.vpc_id
    }
  }

  depends_on = [
    kubectl_manifest.root_app,
    kubectl_manifest.oci_repo,
    helm_release.argocd,
    kubernetes_secret_v1.grafana_admin,
  ]
}
