#!/usr/bin/env bash
# Creates (or updates) the PERMANENT shared layer: ECR, GitHub OIDC role, budgets.
# Usage: bash scripts/shared-up.sh           (asks for your email the first time)
#        ALERT_EMAIL=you@example.com bash scripts/shared-up.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUCKET="${STATE_BUCKET:-terraform-bucket-ajay-2026-xyz}"

EMAIL="${ALERT_EMAIL:-}"
[ -n "$EMAIL" ] || read -r -p "Email address for AWS Budget alerts: " EMAIL

cd "$ROOT/envs/shared"
terraform init -backend-config="bucket=$BUCKET" -reconfigure
terraform apply -var="alert_email=$EMAIL"

ROLE="$(terraform output -raw ci_role_arn)"
echo
echo ">> Shared layer ready."
echo "   GitHub variable (if not set yet):  gh variable set AWS_ROLE_ARN --body \"$ROLE\""
echo "   AWS will email $EMAIL to confirm the budget subscription: open that email."
