variable "region" {
  description = "AWS region for training resources"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "training"
}

variable "name" {
  description = "Base name for all resources"
  type        = string
  default     = "llm-tuning-lab"
}

# Instance Configuration
variable "create_instance" {
  description = "Whether to create the training instance. Set to false to destroy."
  type        = bool
  default     = false
}

variable "instance_type" {
  description = "EC2 instance type (g5.xlarge, g5.2xlarge, p3.2xlarge, etc.)"
  type        = string
  default     = "g5.xlarge"
  
  validation {
    condition     = can(regex("^(g4dn|g5|p3|p4d|p5)\\.", var.instance_type))
    error_message = "Instance type must be a GPU instance (g4dn, g5, p3, p4d, or p5 series)."
  }
}

variable "use_spot" {
  description = "Use spot instances for cost savings (recommended)"
  type        = bool
  default     = true
}

variable "spot_price" {
  description = "Maximum spot price (leave empty for on-demand price)"
  type        = string
  default     = ""
}

variable "volume_size" {
  description = "Root volume size in GB (models + data can be large)"
  type        = number
  default     = 200
}

# Network Configuration
variable "create_vpc" {
  description = "Create a dedicated VPC for training (true) or use existing (false)"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "Existing VPC ID (required if create_vpc is false)"
  type        = string
  default     = null
}

variable "subnet_id" {
  description = "Existing subnet ID (required if create_vpc is false)"
  type        = string
  default     = null
}

variable "availability_zone" {
  description = "Availability zone for the instance (required for spot)"
  type        = string
  default     = "us-west-2a"
}

# SSH Configuration
variable "key_name" {
  description = "EC2 key pair name for SSH access (optional, SSM recommended)"
  type        = string
  default     = null
}

# Training Configuration
variable "docker_image_tag" {
  description = "Docker image tag to use for training"
  type        = string
  default     = "latest"
}

variable "training_command" {
  description = "Command to run inside the container"
  type        = string
  default     = "python -m lab.train_lora --log-level INFO"
}

variable "auto_shutdown" {
  description = "Automatically shutdown instance after training completes"
  type        = bool
  default     = true
}

# Safety Configuration
variable "max_runtime_hours" {
  description = "Maximum runtime before auto-termination (safety net)"
  type        = number
  default     = 12
}

variable "cost_alert_threshold" {
  description = "Cost threshold in USD to trigger alert"
  type        = number
  default     = 50
}

variable "alert_email" {
  description = "Email address for cost and runtime alerts"
  type        = string
  default     = ""
}


