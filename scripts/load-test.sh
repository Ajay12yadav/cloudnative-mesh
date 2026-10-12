#!/usr/bin/env bash
# Generates traffic so the dashboards have something to show.
# Usage: bash scripts/load-test.sh [seconds] [parallel-workers]    (defaults: 120, 5)
set -euo pipefail
DURATION="${1:-120}"
WORKERS="${2:-5}"
LB="$(kubectl get svc -n nginx-ingress nginx-ingress-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
HOST="$(kubectl get ingress cloudnative-app -n app -o jsonpath='{.spec.rules[0].host}')"
END=$(( $(date +%s) + DURATION ))
echo "Sending traffic to http://$LB (host $HOST) for ${DURATION}s with $WORKERS workers..."

worker() {
  while [ "$(date +%s)" -lt "$END" ]; do
    curl -s -o /dev/null -H "Host: $HOST" "http://$LB/api/visits"
    [ $((RANDOM % 5)) -eq 0 ] && curl -s -o /dev/null -X POST -H "Host: $HOST" "http://$LB/api/visit"
    [ $((RANDOM % 15)) -eq 0 ] && curl -s -o /dev/null -H "Host: $HOST" "http://$LB/api/not-a-route"   # a 404 for the status panel
    sleep 0.1
  done
}
for _ in $(seq 1 "$WORKERS"); do worker & done
wait
echo "Done."
