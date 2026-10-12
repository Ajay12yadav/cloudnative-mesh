#!/usr/bin/env bash
# Creates the monitoring namespace and the Grafana admin Secret (random password,
# never stored in Git). Safe to run again: an existing Secret is kept.
set -euo pipefail
CTX="$(kubectl config current-context)"
case "$CTX" in *cnm-dev-eks*) ;; *) echo "STOP: context is '$CTX'"; exit 1 ;; esac

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
if kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
  echo "Secret grafana-admin already exists, keeping it."
else
  PASS="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-20)"
  kubectl -n monitoring create secret generic grafana-admin \
    --from-literal=admin-user=admin --from-literal=admin-password="$PASS"
  echo "Created secret grafana-admin."
fi
echo "Grafana login:  admin / $(kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)"
