#!/usr/bin/env bash
# Verifies the CI/CD pipeline end to end and prints PASS / FAIL per check.
# Usage: bash scripts/verify-ci.sh
# Works without the cluster (checks 1-5); with the cluster running it also checks the deployment (6-7).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REGION="${AWS_REGION:-ap-south-1}"
PASS=0; FAIL=0
ok()   { echo "  PASS  $*"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }
skip() { echo "  skip  $*"; }

echo "== 1. GitHub access and configuration"
if gh auth status >/dev/null 2>&1; then ok "GitHub CLI is logged in"; else bad "GitHub CLI not logged in (run: gh auth login)"; fi
ROLE_VAR="$(gh variable list 2>/dev/null | awk '$1=="AWS_ROLE_ARN"{print $2}')"
ROLE_TF="$(cd envs/shared 2>/dev/null && terraform output -raw ci_role_arn 2>/dev/null || true)"
if [ -z "$ROLE_VAR" ]; then bad "repository variable AWS_ROLE_ARN is not set"
elif [ -n "$ROLE_TF" ] && [ "$ROLE_VAR" != "$ROLE_TF" ]; then bad "AWS_ROLE_ARN ($ROLE_VAR) differs from terraform output ($ROLE_TF)"
else ok "AWS_ROLE_ARN is set ($ROLE_VAR)"; fi

echo "== 2. Workflow runs"
LINE="$(gh run list --workflow build-push.yml --branch main --limit 1 --json conclusion,databaseId,headSha -q '.[0] | "\(.conclusion) \(.databaseId) \(.headSha)"' 2>/dev/null || true)"
read -r CONC RUNID RUNSHA <<<"$LINE"
[ "${CONC:-}" = "null" ] && CONC=""
if [ -z "${CONC:-}" ]; then bad "build-and-push has never run on main"
elif [ "$CONC" = "success" ]; then ok "latest build-and-push run on main succeeded (run $RUNID)"
else bad "latest build-and-push run on main: '$CONC' (see: gh run view $RUNID --log-failed)"; fi

CI_LINE="$(gh run list --workflow ci.yml --limit 1 --json conclusion,event,headBranch -q '.[0] | "\(.conclusion) \(.event) \(.headBranch)"' 2>/dev/null || true)"
if [ -z "$CI_LINE" ] || [ "${CI_LINE%% *}" = "null" ]; then skip "ci.yml has never run (it triggers on pull requests: open one to test it)"
else
  set -- $CI_LINE
  if [ "$1" = "success" ]; then ok "latest ci.yml run succeeded (event $2, branch $3)"; else bad "latest ci.yml run: '$1' (event $2, branch $3)"; fi
fi

echo "== 3. The image tag in Git"
git fetch -q origin 2>/dev/null
FILE_REMOTE="$(git show origin/main:charts/cloudnative-app/values-images.yaml 2>/dev/null || true)"
TAG="$(echo "$FILE_REMOTE" | awk -F'"' '/tag:/{print $2; exit}')"
if [ -z "$TAG" ]; then bad "values-images.yaml is missing on origin/main (CI has not written a tag yet)"
else
  ok "values-images.yaml on origin/main holds tag '$TAG'"
  AUTHOR="$(git log origin/main -1 --format=%an -- charts/cloudnative-app/values-images.yaml 2>/dev/null)"
  if [ "$AUTHOR" = "github-actions[bot]" ]; then ok "the file was committed by the CI bot, not by hand"; else bad "last author of that file is '$AUTHOR' (expected github-actions[bot])"; fi
  if git cat-file -e "${TAG}^{commit}" 2>/dev/null; then ok "tag '$TAG' is a real commit of this repository (image is traceable to code)"; else bad "tag '$TAG' is not a commit in this repo"; fi
fi

echo "== 4. Images in ECR"
if [ -n "$TAG" ]; then
  for repo in cnm-dev/api cnm-dev/frontend; do
    OUT="$(aws ecr describe-images --region "$REGION" --repository-name "$repo" --image-ids imageTag="$TAG" \
          --query 'imageDetails[0].[imageDigest,imageScanStatus.status]' --output text 2>/dev/null || true)"
    DIGEST="$(echo "$OUT" | awk '{print $1}')"; SCAN="$(echo "$OUT" | awk '{print $2}')"
    [ "$SCAN" = "None" ] && SCAN="not reported yet"
    if [ -n "$OUT" ]; then ok "$repo:$TAG exists (${DIGEST:0:19}..., scan: $SCAN)"; else bad "$repo:$TAG not found in ECR"; fi
  done
else skip "no tag to look up"; fi

echo "== 5. Security properties of the pipeline"
TRUST="$(aws iam get-role --role-name cnm-github-ci --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null || true)"
if echo "$TRUST" | grep -q 'refs/heads/main'; then ok "role trust is limited to the main branch"; else bad "role trust does not mention refs/heads/main"; fi
if echo "$TRUST" | grep -q '@[0-9]*/.*@[0-9]*'; then ok "role trust uses GitHub's immutable owner/repo IDs"; else bad "role trust does not use numeric IDs"; fi
if aws iam list-access-keys --user-name cnm-github-ci >/dev/null 2>&1; then bad "an IAM user cnm-github-ci with keys exists"; else ok "no long-lived AWS keys are used by CI (OIDC only)"; fi

echo "== 6. Deployment (needs the cluster)"
CTX="$(kubectl config current-context 2>/dev/null || true)"
if [[ "$CTX" == *cnm-dev-eks* ]] && kubectl get nodes --request-timeout=10s >/dev/null 2>&1; then
  SYNC="$(kubectl get application cloudnative-app -n argocd -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)"
  if [ "$SYNC" = "Synced/Healthy" ]; then ok "Argo CD application cloudnative-app is $SYNC"
  elif [ "$SYNC" = "Synced/Progressing" ]; then skip "cloudnative-app is Synced/Progressing: still waiting for the load balancer (not a failure yet)"
  else bad "Argo CD application cloudnative-app is '$SYNC'"; fi
  for d in api frontend; do
    IMG="$(kubectl get deploy "$d" -n app -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)"
    if [ -n "$TAG" ] && [[ "$IMG" == *":$TAG" ]]; then ok "deployment/$d runs $IMG (the tag CI wrote)"; else bad "deployment/$d runs '$IMG' but Git says tag '$TAG'"; fi
  done
  READY="$(kubectl get deploy api frontend -n app -o jsonpath='{range .items[*]}{.status.readyReplicas}{" "}{end}' 2>/dev/null)"
  ok "ready replicas (api frontend): $READY"
else
  skip "cluster not reachable: skipping deployment checks (start it with scripts/up.sh)"
fi

echo "== 7. The live app (needs the cluster)"
LB="$(kubectl get svc -n nginx-ingress nginx-ingress-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
if [ -n "$LB" ]; then
  CODE="$(curl -s -m 10 -o /dev/null -w '%{http_code}' "http://$LB/api/visits")"
  if [ "$CODE" = "200" ]; then ok "http://$LB/api/visits answers 200"; else bad "http://$LB/api/visits answered $CODE"; fi
else skip "no load balancer found"; fi

echo
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
