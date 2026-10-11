#!/usr/bin/env bash
# Build both images and push them to ECR.
# Usage:  ./scripts/build-push.sh [tag]      (default tag: v1)
set -euo pipefail

TAG="${1:-v1}"
REGION="${AWS_REGION:-ap-south-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

API_REPO="$(cd "$ROOT/envs/dev" && terraform output -raw ecr_api_url)"
FRONT_REPO="$(cd "$ROOT/envs/dev" && terraform output -raw ecr_frontend_url)"
REGISTRY="${API_REPO%%/*}"

echo ">> Logging in to $REGISTRY"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

# --platform: our EKS nodes are x86_64 (t3). This also works from ARM laptops.
echo ">> Building API ($API_REPO:$TAG)"
docker build --platform linux/amd64 -t "$API_REPO:$TAG" "$ROOT/app/api"
docker push "$API_REPO:$TAG"

echo ">> Building frontend ($FRONT_REPO:$TAG)"
docker build --platform linux/amd64 -t "$FRONT_REPO:$TAG" "$ROOT/app/frontend"
docker push "$FRONT_REPO:$TAG"

echo ">> Done. Images pushed with tag '$TAG':"
echo "   $API_REPO:$TAG"
echo "   $FRONT_REPO:$TAG"
