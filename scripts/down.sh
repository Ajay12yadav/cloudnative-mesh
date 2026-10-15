#!/usr/bin/env bash
# Safe teardown. Destroys the platform layer first (its cleanup removes the load
# balancer and EBS volumes that Kubernetes created), then the infrastructure.
# The shared layer (ECR, OIDC role, budgets) and the state bucket are kept.
# Usage: bash scripts/down.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUCKET="${STATE_BUCKET:-terraform-bucket-ajay-2026-xyz}"
REGION="${AWS_REGION:-ap-south-1}"

echo "=== 1/2 Platform layer ==="
cd "$ROOT/envs/platform"
terraform init -backend-config="bucket=$BUCKET" -reconfigure
if aws eks describe-cluster --region "$REGION" --name cnm-dev-eks >/dev/null 2>&1; then
  terraform destroy -auto-approve
else
  echo "Cluster no longer exists: dropping the platform state without calling Kubernetes."
  terraform state list | grep -v '^data\.' | xargs -r -n1 terraform state rm || true
fi

echo "=== 2/2 Infrastructure layer ==="
cd "$ROOT/envs/dev"
terraform init -backend-config="bucket=$BUCKET" -reconfigure
terraform destroy -auto-approve

echo ">> Done. Verify nothing is left:  ~/aws-check.sh ap-south-1"
