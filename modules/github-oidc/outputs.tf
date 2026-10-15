output "role_arn" {
  description = "Put this in the GitHub repository variable AWS_ROLE_ARN"
  value       = aws_iam_role.ci.arn
}
