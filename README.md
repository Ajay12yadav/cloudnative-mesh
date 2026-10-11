# CloudNative-Mesh

| Step | Folder(s) | Status |
|------|-----------|--------|
| 1 | bootstrap/, modules/vpc, envs/dev | done |
| 2 | modules/rds, modules/redis, envs/dev | done |
| 3 | modules/eks, envs/dev | done |
| 4a | modules/ecr, app/, scripts/ | done |

    cd envs/dev
    terraform init -backend-config="bucket=<your-state-bucket>"
    terraform validate && terraform plan && terraform apply
    terraform destroy   # when finished for the day
