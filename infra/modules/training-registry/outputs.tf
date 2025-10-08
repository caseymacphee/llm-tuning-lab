output "repository_url" {
  description = "ECR repository URL"
  value       = aws_ecr_repository.training.repository_url
}

output "repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.training.arn
}

output "repository_name" {
  description = "ECR repository name"
  value       = aws_ecr_repository.training.name
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "GitHub OIDC provider ARN"
  value       = local.oidc_provider_arn
}

