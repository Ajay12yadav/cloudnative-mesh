#!/usr/bin/env bash
# Called by Terraform (envs/platform) when the platform layer is DESTROYED.
# Removes what Kubernetes created outside Terraform: load balancers and EBS volumes.
# Exits non-zero if anything is left, which stops the destroy before the VPC is touched.
set -uo pipefail
REGION="${REGION:?}"; CLUSTER="${CLUSTER:?}"; VPC_ID="${VPC_ID:?}"

aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER" >/dev/null

echo ">> Deleting Argo CD applications (cascades to pods, services and the AWS load balancer)"
kubectl delete applications --all -n argocd --wait=true --timeout=600s || echo "   (continuing)"

echo ">> Deleting volume claims (Prometheus, Grafana)"
kubectl delete pvc --all -A --wait=true --timeout=300s || true
for i in $(seq 1 30); do
  [ -z "$(kubectl get pv -o name 2>/dev/null)" ] && break
  echo "   waiting for persistent volumes to be deleted ($i/30)..."; sleep 10
done
if [ -n "$(kubectl get pv -o name 2>/dev/null)" ]; then
  echo "ERROR: persistent volumes still exist; refusing to continue (they would be orphaned)."; exit 1
fi

echo ">> Waiting for load balancers in the VPC to disappear"
for i in $(seq 1 60); do
  LBS="$(aws elbv2 describe-load-balancers --region "$REGION" \
        --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" --output text 2>/dev/null || true)"
  if [ -z "$LBS" ]; then echo ">> Cluster is clean."; exit 0; fi
  echo "   still deleting ($i/60)..."; sleep 10
done
echo "ERROR: load balancers still exist in the VPC:"; echo "$LBS"; exit 1
