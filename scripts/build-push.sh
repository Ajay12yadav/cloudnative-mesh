#!/usr/bin/env bash
# EMERGENCY / MANUAL image push (normally GitHub Actions does this).
# Tags are immutable in ECR, so every push needs a NEW tag.
# Usage: bash scripts/build-push.sh <new-tag>
set -euo pipefail

TAG="${1:?usage: build-push.sh <new-tag>   (tags are immutable; use a new one each time)}"
REGION="${AWS_REGION:-ap-south-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

API_REPO="$(cd "$ROOT/envs/shared" && terraform output -raw ecr_api_url)"
FRONT_REPO="$(cd "$ROOT/envs/shared" && terraform output -raw ecr_frontend_url)"
REGISTRY="${API_REPO%%/*}"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

docker build --platform linux/amd64 -t "$API_REPO:$TAG" "$ROOT/app/api"
docker push "$API_REPO:$TAG"
docker build --platform linux/amd64 -t "$FRONT_REPO:$TAG" "$ROOT/app/frontend"
docker push "$FRONT_REPO:$TAG"

echo "Pushed tag '$TAG'. To deploy it, put it in charts/cloudnative-app/values-images.yaml and push to Git."
