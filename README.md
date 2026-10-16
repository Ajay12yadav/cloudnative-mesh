# CloudNative-Mesh

| Step | Folder(s) | Status |
|------|-----------|--------|
| 1 | bootstrap/, modules/vpc, envs/dev | done |
| 2 | modules/rds, modules/redis, envs/dev | done |
| 3 | modules/eks, envs/dev | done |
| 4a | modules/ecr, app/, scripts/ | done |
| 4b | modules/irsa, k8s/platform, charts/ | done |
| 5 | gitops/, scripts/up.sh, down.sh, bootstrap-argocd.sh | done |
| 6 | k8s/monitoring, gitops/apps/monitoring*.yaml | done |
| 7e | .github/workflows, envs/shared, modules/github-oidc | done |
| 7c | budgets in envs/shared | done |
| 7a | envs/platform (Argo CD, secrets, safe teardown) | done |

    cd envs/dev
    terraform init -backend-config="bucket=<your-state-bucket>"
    terraform validate && terraform plan && terraform apply
    terraform destroy   # when finished for the day

## Daily workflow

    bash scripts/up.sh      # rebuild everything (about 25-30 min)
    bash scripts/down.sh    # tear everything down safely

## CI/CD flow

    pull request  -> ci.yml          (terraform validate, helm lint, tests, image build + scan; no AWS access)
    merge to main -> build-push.yml  (build images, push to ECR tagged with the commit SHA,
                                      write the tag to charts/cloudnative-app/values-images.yaml)
    Argo CD       -> sees the new tag in Git and rolls it out

Permanent layer (never destroyed by down.sh): `bash scripts/shared-up.sh`  (ECR + GitHub OIDC role)

## Layers (separate Terraform state files)

| Layer | Folder | Lifetime |
|---|---|---|
| Bootstrap | bootstrap/ | permanent (state bucket) |
| Shared | envs/shared | permanent (ECR, GitHub OIDC role, budgets) |
| Infrastructure | envs/dev | daily (VPC, EKS, RDS, Redis, IAM) |
| Platform | envs/platform | daily (Argo CD, secrets, root app, safe-teardown hook) |

    bash scripts/up.sh      # dev -> values -> platform
    bash scripts/down.sh    # platform (cleans LB/EBS) -> dev

