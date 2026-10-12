#!/usr/bin/env bash
# Port-forwards Grafana to http://localhost:3000 and prints the login.
# Usage: bash scripts/open-grafana.sh      (Ctrl+C to stop)
set -euo pipefail
echo "URL:      http://localhost:3000"
echo "User:     admin"
echo "Password: $(kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)"
kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80
