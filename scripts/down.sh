#!/usr/bin/env bash
# Safe teardown: remove what KUBERNETES created (load balancer, volumes) BEFORE terraform destroy.
# Usage: bash scripts/down.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUCKET="${STATE_BUCKET:-terraform-bucket-ajay-2026-xyz}"
REGION="${AWS_REGION:-ap-south-1}"

CTX="$(kubectl config current-context)"
case "$CTX" in
  *cnm-dev-eks*) ;;
  *) echo "STOP: kubectl context is '$CTX', not the EKS cluster."; exit 1 ;;
esac

VPC_ID="$(cd envs/dev && terraform output -raw vpc_id)"

echo ">> Deleting Argo CD applications (cascades to pods, services, and the AWS load balancer)"
kubectl delete applications --all -n argocd --wait=true --timeout=600s || true

echo ">> Deleting any leftover volume claims"
kubectl delete pvc --all -A --wait=false || true

echo ">> Waiting for Kubernetes-created load balancers in the VPC to disappear"
for i in $(seq 1 30); do
  LBS="$(aws elbv2 describe-load-balancers --region "$REGION" \
        --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text 2>/dev/null || true)"
  [ -z "$LBS" ] && break
  echo "   still deleting ($i/30)..."; sleep 10
done

helm uninstall argocd -n argocd || true

echo ">> Terraform destroy"
cd envs/dev
terraform init -backend-config="bucket=$BUCKET" -reconfigure
terraform destroy -auto-approve

echo ">> Done. Verify nothing is left:  ~/aws-check.sh ap-south-1"
