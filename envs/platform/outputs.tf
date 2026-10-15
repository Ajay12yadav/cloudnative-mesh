output "argocd_namespace" {
  value = helm_release.argocd.namespace
}

output "grafana_admin_password" {
  description = "terraform output -raw grafana_admin_password"
  value       = random_password.grafana.result
  sensitive   = true
}
