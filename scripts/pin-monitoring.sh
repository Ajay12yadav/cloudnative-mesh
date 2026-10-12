#!/usr/bin/env bash
# Pins the kube-prometheus-stack chart version in gitops/apps/monitoring.yaml.
# Usage: bash scripts/pin-monitoring.sh            -> newest chart version
#        bash scripts/pin-monitoring.sh 80.1.0     -> a specific version
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update prometheus-community >/dev/null

VER="${1:-$(helm search repo prometheus-community/kube-prometheus-stack -o json | python3 -c 'import sys,json; print(json.load(sys.stdin)[0]["version"])')}"

python3 - "$VER" <<'PY'
import re, sys
ver = sys.argv[1]
p = "gitops/apps/monitoring.yaml"
lines = open(p).read().split("\n")
for i, l in enumerate(lines):
    if "chart: kube-prometheus-stack" in l:
        for j in range(i + 1, i + 4):
            if "targetRevision:" in lines[j]:
                lines[j] = re.sub(r"(targetRevision:\s*)\S+", r"\g<1>" + ver, lines[j], count=1)
                break
open(p, "w").write("\n".join(lines))
PY
echo "Pinned kube-prometheus-stack chart to: $VER"
grep -n -B1 -A1 "targetRevision: $VER" gitops/apps/monitoring.yaml | head -5
echo "Commit and push it:  git add gitops && git commit -m 'Pin monitoring chart' && git push"
