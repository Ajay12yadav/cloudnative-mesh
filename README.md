# CloudNative-Mesh
Step 1: remote state + VPC.

    cd bootstrap && terraform init && terraform apply -var="state_bucket_name=<unique-name>"
    cd ../envs/dev && terraform init -backend-config="bucket=<unique-name>"
    terraform plan && terraform apply
