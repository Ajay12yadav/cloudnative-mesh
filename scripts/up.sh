#!/usr/bin/env bash
# One command to rebuild the WHOLE platform after a teardown (about 25-30 minutes).
# Usage: bash scripts/up.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUCKET="${STATE_BUCKET:-terraform-bucket-ajay-2026-xyz}"
REGION="${AWS_REGION:-ap-south-1}"

echo "=== 1/7 Terraform: network, RDS, Redis, EKS, ECR, IAM ==="
( cd envs/dev
  terraform init -backend-config="bucket=$BUCKET" -reconfigure
  terraform apply -auto-approve )

echo "=== 2/7 Connect kubectl to the new cluster ==="
aws eks update-kubeconfig --region "$REGION" --name cnm-dev-eks
kubectl get nodes

echo "=== 3/7 Build and push images (the ECR repos are new and empty) ==="
bash scripts/build-push.sh v1

echo "=== 4/7 Make gp3 the only default StorageClass ==="
kubectl patch storageclass gp2 -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' || true

echo "=== 5/7 Regenerate values (new secret ARN / endpoints) and push to Git ==="
bash scripts/gen-values.sh v1
bash scripts/set-repo-url.sh
git add charts/cloudnative-app/values-dev.yaml gitops
git diff --cached --quiet || git commit -m "Rebuild: refresh values-dev.yaml"
git push

echo "=== 6/7 Grafana admin secret, then install Argo CD and hand over to Git ==="
bash scripts/monitoring-secrets.sh
bash scripts/bootstrap-argocd.sh

echo "=== 7/7 Wait for the load balancer and set the Ingress host ==="
bash scripts/set-host.sh
