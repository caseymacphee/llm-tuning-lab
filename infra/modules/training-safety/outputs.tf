output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value       = local.create_resources && var.alert_email != "" ? aws_sns_topic.alerts[0].arn : null
}

output "lambda_function_name" {
  description = "Lambda function name for auto-termination"
  value       = local.create_resources ? aws_lambda_function.auto_terminate[0].function_name : null
}

output "budget_name" {
  description = "Budget name for cost alerts"
  value       = local.create_resources && var.cost_alert_threshold > 0 ? aws_budgets_budget.training[0].name : null
}


