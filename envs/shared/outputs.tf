output "ecr_api_url" { value = module.ecr.repository_urls["api"] }
output "ecr_frontend_url" { value = module.ecr.repository_urls["frontend"] }
output "ci_role_arn" {
  description = "Value for the GitHub repository variable AWS_ROLE_ARN"
  value       = module.github_oidc.role_arn
}
