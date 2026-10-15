#!/usr/bin/env bash
# Creates (or updates) the PERMANENT shared layer: ECR + GitHub OIDC role.
# Usage: bash scripts/shared-up.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUCKET="${STATE_BUCKET:-terraform-bucket-ajay-2026-xyz}"
cd "$ROOT/envs/shared"
terraform init -backend-config="bucket=$BUCKET" -reconfigure
terraform apply

ROLE="$(terraform output -raw ci_role_arn)"
echo
echo ">> Shared layer ready."
echo "   Now tell GitHub which role to use (a repository VARIABLE, not a secret):"
echo "     gh variable set AWS_ROLE_ARN --body \"$ROLE\""
echo "   or in the browser: repo -> Settings -> Secrets and variables -> Actions -> Variables -> New repository variable"
echo "     Name:  AWS_ROLE_ARN"
echo "     Value: $ROLE"
