variable "name" {
  description = "Base name for resources"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "create_instance" {
  description = "Whether to create the training instance"
  type        = bool
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "use_spot" {
  description = "Use spot instances"
  type        = bool
}

variable "spot_price" {
  description = "Maximum spot price"
  type        = string
}

variable "volume_size" {
  description = "Root volume size in GB"
  type        = number
}

variable "create_vpc" {
  description = "Create a dedicated VPC"
  type        = bool
}

variable "vpc_id" {
  description = "Existing VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Existing subnet ID"
  type        = string
}

variable "availability_zone" {
  description = "Availability zone"
  type        = string
}

variable "key_name" {
  description = "EC2 key pair name"
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL"
  type        = string
}

variable "training_bucket" {
  description = "S3 training data bucket name"
  type        = string
}

variable "outputs_bucket" {
  description = "S3 outputs bucket name"
  type        = string
}

variable "docker_image_tag" {
  description = "Docker image tag"
  type        = string
}

variable "training_command" {
  description = "Training command to run"
  type        = string
}

variable "auto_shutdown" {
  description = "Auto-shutdown after training"
  type        = bool
}


