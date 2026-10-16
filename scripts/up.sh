#!/usr/bin/env bash
# One command to rebuild the platform after a teardown (about 25 minutes).
# Terraform builds the infrastructure (envs/dev) AND the platform on top (envs/platform).
# Images are NOT rebuilt: they live permanently in ECR and CI owns their tags.
# Usage: bash scripts/up.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BUCKET="${STATE_BUCKET:-terraform-bucket-ajay-2026-xyz}"
REGION="${AWS_REGION:-ap-south-1}"

echo "=== 0/6 Pre-flight checks ==="
git pull --rebase --autostash        # CI commits image tags to GitHub: get them first

IMG_FILE=charts/cloudnative-app/values-images.yaml
if [ ! -f "$IMG_FILE" ]; then
  echo "STOP: $IMG_FILE does not exist yet."
  echo "      Run the CI once: GitHub -> Actions -> build-and-push -> Run workflow, then 'git pull'."
  exit 1
fi
TAG="$(awk -F'"' '/tag:/{print $2; exit}' "$IMG_FILE")"
for repo in cnm-dev/api cnm-dev/frontend; do
  aws ecr describe-images --region "$REGION" --repository-name "$repo" --image-ids imageTag="$TAG" >/dev/null \
    || { echo "STOP: image $repo:$TAG is not in ECR. Re-run the CI workflow."; exit 1; }
done
echo "Image tag $TAG exists in ECR."

echo "=== 1/6 Terraform (envs/dev): network, RDS, Redis, EKS, IAM ==="
( cd envs/dev
  terraform init -backend-config="bucket=$BUCKET" -reconfigure
  terraform apply -auto-approve )

echo "=== 2/6 Connect kubectl to the new cluster ==="
aws eks update-kubeconfig --region "$REGION" --name cnm-dev-eks
kubectl get nodes

echo "=== 3/6 Make gp3 the only default StorageClass ==="
kubectl patch storageclass gp2 -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' || true

echo "=== 4/6 Regenerate values (new secret ARN / endpoints) and push to Git ==="
bash scripts/gen-values.sh
bash scripts/set-repo-url.sh
git add charts/cloudnative-app/values-dev.yaml gitops
git diff --cached --quiet || git commit -m "Rebuild: refresh values-dev.yaml"
git pull --rebase --autostash
git push

echo "=== 5/6 Terraform (envs/platform): Argo CD, Grafana secret, root app ==="
( cd envs/platform
  terraform init -backend-config="bucket=$BUCKET" -reconfigure
  terraform apply -auto-approve )

echo "=== 6/6 Wait for the load balancer and set the Ingress host ==="
if [ "${SKIP_HOST:-0}" = "1" ]; then
  echo "SKIP_HOST=1: skipping the load balancer wait (use: kubectl port-forward to reach the app)."
else
  bash scripts/set-host.sh
fi
