#!/usr/bin/env bash
# FINAL CI/CD TEST: proves a code change travels from "git push" to the running cluster,
# with no manual deploy command, and (optionally) that a rollback works.
#
# Usage:  bash scripts/e2e-ci-test.sh                      # forward test (through the load balancer)
#         bash scripts/e2e-ci-test.sh --rollback           # forward test, then roll back through Git
#         bash scripts/e2e-ci-test.sh --no-lb [--rollback] # no load balancer: reach NGINX with kubectl port-forward
# Needs: the platform up (scripts/up.sh), gh logged in, a clean git working tree.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
IMG_FILE=charts/cloudnative-app/values-images.yaml

ROLLBACK=0; NO_LB=0
for arg in "$@"; do
  case "$arg" in
    --rollback) ROLLBACK=1 ;;
    --no-lb)    NO_LB=1 ;;
    *) echo "unknown option: $arg"; exit 2 ;;
  esac
done

fail() { echo; echo "FAILED: $*"; exit 1; }
wait_for() {   # wait_for "<description>" <timeout-seconds> <command...>
  local desc="$1" timeout="$2"; shift 2
  local start=$SECONDS
  until "$@" >/dev/null 2>&1; do
    [ $((SECONDS - start)) -ge "$timeout" ] && fail "timed out after ${timeout}s waiting for: $desc"
    sleep 10
  done
  echo "   ok: $desc ($((SECONDS - start))s)"
}
tag_in_file() { awk -F'"' '/tag:/{print $2; exit}' "$IMG_FILE"; }

echo "== Pre-flight"
CTX="$(kubectl config current-context)"
[[ "$CTX" == *cnm-dev-eks* ]] || fail "kubectl context is '$CTX', not the EKS cluster"
kubectl get nodes --request-timeout=15s >/dev/null || fail "cluster unreachable (did your IP change? see terraform.tfvars)"
gh auth status >/dev/null 2>&1 || fail "gh is not logged in"
git diff --quiet && git diff --cached --quiet || fail "git working tree is not clean: commit or stash first"
git pull -q --rebase
OLD_TAG="$(tag_in_file)"
if [ "$NO_LB" = 1 ]; then
  HOST="$(kubectl get ingress cloudnative-app -n app -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || true)"
  [ -n "$HOST" ] || fail "no Ingress 'cloudnative-app' found in namespace app"
  kubectl port-forward -n nginx-ingress svc/nginx-ingress-controller 18080:80 >/tmp/e2e-portforward.log 2>&1 &
  PF_PID=$!
  trap 'kill $PF_PID 2>/dev/null || true' EXIT
  sleep 5
  kill -0 "$PF_PID" 2>/dev/null || fail "port-forward failed: $(cat /tmp/e2e-portforward.log)"
  BASE="http://127.0.0.1:18080"
else
  echo "   waiting for the load balancer and the ingress (up to 15 minutes)..."
  LB=""; HOST=""
  for _ in $(seq 1 90); do
    LB="$(kubectl get svc -n nginx-ingress nginx-ingress-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    HOST="$(kubectl get ingress cloudnative-app -n app -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || true)"
    [ -n "$LB" ] && [ -n "$HOST" ] && break
    sleep 10
  done
  [ -n "$LB" ] && [ -n "$HOST" ] || fail "still no load balancer after 15 minutes. If AWS refuses to create it, re-run with --no-lb. Check: kubectl describe svc -n nginx-ingress nginx-ingress-controller"
  BASE="http://$LB"
fi
echo "   current tag: $OLD_TAG    app: $BASE (Host: $HOST)"

echo "== 1. Make a visible change and push it"
STAMP="$(date +%Y%m%d-%H%M%S)"
python3 - "$STAMP" <<'PY'
import re, sys
stamp = sys.argv[1]
p = "app/frontend/index.html"
s = open(p).read()
meta = f'<meta name="build-id" content="{stamp}">'
if 'name="build-id"' in s:
    s = re.sub(r'<meta name="build-id" content="[^"]*">', meta, s)
else:
    s = s.replace("<title>CloudNative-Mesh</title>", "<title>CloudNative-Mesh</title>\n  " + meta)
open(p, "w").write(s)
PY
git add app/frontend/index.html
git commit -q -m "e2e test: build id $STAMP"
SHA="$(git rev-parse --short=7 HEAD)"
T0=$SECONDS
git push -q
echo "   pushed commit $SHA (build id $STAMP). Expected new image tag: $SHA"

echo "== 2. GitHub Actions builds and pushes the images"
RUN=""
for _ in $(seq 1 30); do
  RUN="$(gh run list --workflow build-push.yml --limit 10 --json databaseId,headSha \
        -q ".[] | select(.headSha | startswith(\"$SHA\")) | .databaseId" | head -1)"
  [ -n "$RUN" ] && break
  sleep 5
done
[ -n "$RUN" ] || fail "no build-and-push run started for commit $SHA"
echo "   run $RUN started; waiting for it to finish..."
gh run watch "$RUN" --exit-status >/dev/null || fail "workflow failed. Inspect: gh run view $RUN --log-failed"
T1=$SECONDS
echo "   workflow succeeded"

echo "== 3. The CI bot wrote the new tag into Git"
tag_matches() { git pull -q --rebase && [ "$(tag_in_file)" = "$SHA" ]; }
wait_for "values-images.yaml holds tag $SHA" 120 tag_matches
T2=$SECONDS

echo "== 4. Argo CD rolls the new images out (no helm, no kubectl apply by you)"
kubectl annotate application cloudnative-app -n argocd argocd.argoproj.io/refresh=hard --overwrite >/dev/null
deployed() { [[ "$(kubectl get deploy frontend -n app -o jsonpath='{.spec.template.spec.containers[0].image}')" == *":$SHA" ]]; }
wait_for "deployment/frontend uses image tag $SHA" 300 deployed
kubectl rollout status deploy/frontend -n app --timeout=300s >/dev/null
kubectl rollout status deploy/api -n app --timeout=300s >/dev/null
T3=$SECONDS
echo "   rollout complete"

echo "== 5. The live site serves the new build"
live() { curl -s -m 10 -H "Host: $HOST" "$BASE/" | grep -q "$STAMP"; }
wait_for "$BASE/ contains build id $STAMP" 180 live
T4=$SECONDS

echo
echo "RESULT: PASS. A pushed commit reached the live site with no manual deployment."
echo "   push -> workflow finished : $((T1 - T0))s"
echo "   -> tag committed to Git   : $((T2 - T0))s"
echo "   -> pods running new image : $((T3 - T0))s"
echo "   -> live page shows change : $((T4 - T0))s  (commit-to-live)"

if [ "$ROLLBACK" = 1 ]; then
  echo
  echo "== 6. Rollback through Git (revert the bot's tag commit)"
  BOT_COMMIT="$(git log -1 --format=%H -- "$IMG_FILE")"
  git revert --no-edit "$BOT_COMMIT" >/dev/null
  git push -q
  R0=$SECONDS
  [ "$(tag_in_file)" = "$OLD_TAG" ] || fail "revert did not restore tag $OLD_TAG (is: $(tag_in_file))"
  kubectl annotate application cloudnative-app -n argocd argocd.argoproj.io/refresh=hard --overwrite >/dev/null
  rolled_back() { [[ "$(kubectl get deploy frontend -n app -o jsonpath='{.spec.template.spec.containers[0].image}')" == *":$OLD_TAG" ]]; }
  wait_for "deployment/frontend back on $OLD_TAG" 300 rolled_back
  kubectl rollout status deploy/frontend -n app --timeout=300s >/dev/null
  gone() { ! curl -s -m 10 -H "Host: $HOST" "$BASE/" | grep -q "$STAMP"; }
  wait_for "live page no longer shows $STAMP" 180 gone
  echo
  echo "RESULT: ROLLBACK PASS in $((SECONDS - R0))s (git revert only; no workflow, no kubectl)."
  echo "   Note: the source change is still on main. Only the deployment went back."
fi
