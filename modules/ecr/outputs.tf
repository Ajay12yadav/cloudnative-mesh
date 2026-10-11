output "repository_urls" {
  description = "Map of repo key -> full URL (account.dkr.ecr.region.amazonaws.com/name)"
  value       = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}
