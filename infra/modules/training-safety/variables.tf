variable "name" {
  description = "Base name for resources"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "instance_id" {
  description = "EC2 instance ID to monitor"
  type        = string
}

variable "max_runtime_hours" {
  description = "Maximum runtime before auto-termination"
  type        = number
}

variable "cost_alert_threshold" {
  description = "Cost threshold for alerts"
  type        = number
}

variable "alert_email" {
  description = "Email for alerts"
  type        = string
}

variable "create_safety_resources" {
  description = "Whether to create safety resources"
  type        = bool
}


