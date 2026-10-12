#!/usr/bin/env bash
# Installs Argo CD on the CURRENT cluster and hands control to Git.
# Usage: bash scripts/bootstrap-argocd.sh
# Private repo? export GITHUB_USER and GITHUB_TOKEN (a PAT with repo read access) first.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CTX="$(kubectl config current-context)"
case "$CTX" in
  *cnm-dev-eks*) ;;
  *) echo "STOP: current kubectl context is '$CTX', not the EKS cluster."; exit 1 ;;
esac

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null

# Pin with ARGOCD_CHART_VERSION=x.y.z; otherwise use the newest chart and show which.
if [ -z "${ARGOCD_CHART_VERSION:-}" ]; then
  ARGOCD_CHART_VERSION="$(helm search repo argo/argo-cd -o json | python3 -c 'import sys,json; print(json.load(sys.stdin)[0]["version"])')"
fi
echo ">> Installing Argo CD chart version $ARGOCD_CHART_VERSION (pin it next time: ARGOCD_CHART_VERSION=$ARGOCD_CHART_VERSION)"

helm upgrade --install argocd argo/argo-cd \
  --version "$ARGOCD_CHART_VERSION" \
  --namespace argocd --create-namespace \
  -f gitops/bootstrap/argocd-values.yaml \
  --wait --timeout 10m

if [ -n "${GITHUB_TOKEN:-}" ]; then
  echo ">> Registering private repo credentials"
  REPO_URL="$(grep -m1 -E 'repoURL: https://github.com' gitops/bootstrap/root-app.yaml | awk '{print $2}')"
  kubectl -n argocd create secret generic repo-cloudnative-mesh \
    --from-literal=type=git --from-literal=url="$REPO_URL" \
    --from-literal=username="${GITHUB_USER:?set GITHUB_USER}" --from-literal=password="$GITHUB_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n argocd label secret repo-cloudnative-mesh argocd.argoproj.io/secret-type=repository --overwrite
fi

kubectl apply -f gitops/bootstrap/oci-repo-nginx.yaml
kubectl apply -f gitops/bootstrap/root-app.yaml

echo
echo ">> Done. Argo CD is now deploying everything from Git."
echo "   Watch:    kubectl get applications -n argocd -w"
echo "   UI:       kubectl port-forward -n argocd svc/argocd-server 8080:80   (http://localhost:8080)"
echo "   User:     admin"
echo "   Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
