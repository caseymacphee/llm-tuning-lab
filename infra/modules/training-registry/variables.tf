variable "name" {
  description = "Base name for resources"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "github_owner" {
  description = "GitHub repository owner/organization"
  type        = string
  default     = "caseymacphee"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "llm-tuning-lab"
}

variable "github_branch" {
  description = "GitHub branch that can push to ECR"
  type        = string
  default     = "main"
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN (leave empty to create new)"
  type        = string
  default     = ""
}

