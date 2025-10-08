terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.50"
    }
  }
  
  # Optional: Configure backend for state management
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "llm-tuning-lab/training/terraform.tfstate"
  #   region = "us-west-2"
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "llm-tuning-lab"
      Environment = var.environment
      ManagedBy   = "terraform"
      Purpose     = "ml-training"
    }
  }
}

# Training data and outputs storage
module "storage" {
  source      = "../../modules/training-storage"
  name        = var.name
  environment = var.environment
  region      = var.region
}

# Container registry for training images
module "registry" {
  source      = "../../modules/training-registry"
  name        = var.name
  environment = var.environment
}

# GPU compute instance for training
module "compute" {
  source = "../../modules/training-compute"
  
  # Instance configuration
  create_instance = var.create_instance
  name            = var.name
  environment     = var.environment
  instance_type   = var.instance_type
  use_spot        = var.use_spot
  spot_price      = var.spot_price
  volume_size     = var.volume_size
  
  # Network configuration
  vpc_id            = var.vpc_id
  subnet_id         = var.subnet_id
  create_vpc        = var.create_vpc
  availability_zone = var.availability_zone
  
  # Dependencies
  ecr_repository_url = module.registry.repository_url
  training_bucket    = module.storage.training_bucket_name
  outputs_bucket     = module.storage.outputs_bucket_name
  
  # SSH key (optional)
  key_name = var.key_name
  
  # Training script configuration
  docker_image_tag    = var.docker_image_tag
  training_command    = var.training_command
  auto_shutdown       = var.auto_shutdown
}

# Safety features and monitoring
module "safety" {
  source = "../../modules/training-safety"
  
  name                = var.name
  environment         = var.environment
  instance_id         = module.compute.instance_id
  max_runtime_hours   = var.max_runtime_hours
  cost_alert_threshold = var.cost_alert_threshold
  alert_email         = var.alert_email
  
  # Only create safety resources if instance is created
  create_safety_resources = var.create_instance
}

# Outputs
output "training_bucket" {
  description = "S3 bucket for training data"
  value       = module.storage.training_bucket_name
}

output "outputs_bucket" {
  description = "S3 bucket for training outputs"
  value       = module.storage.outputs_bucket_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for Docker images"
  value       = module.registry.repository_url
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions (add this to GitHub secrets)"
  value       = module.registry.github_actions_role_arn
}

output "instance_id" {
  description = "EC2 instance ID (if created)"
  value       = module.compute.instance_id
}

output "ssm_connect_command" {
  description = "Command to connect via AWS Systems Manager"
  value       = module.compute.ssm_connect_command
}

output "public_ip" {
  description = "Public IP address (if instance created)"
  value       = module.compute.public_ip
}

output "instance_state" {
  description = "Current state of the training instance"
  value       = module.compute.instance_state
}

