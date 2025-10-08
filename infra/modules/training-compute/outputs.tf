output "instance_id" {
  description = "EC2 instance ID"
  value       = var.create_instance ? aws_instance.training[0].id : null
}

output "public_ip" {
  description = "Public IP address"
  value       = var.create_instance ? aws_instance.training[0].public_ip : null
}

output "ssm_connect_command" {
  description = "Command to connect via SSM"
  value       = var.create_instance ? "aws ssm start-session --target ${aws_instance.training[0].id}" : null
}

output "instance_state" {
  description = "Instance state"
  value       = var.create_instance ? aws_instance.training[0].instance_state : "not_created"
}

output "vpc_id" {
  description = "VPC ID"
  value       = local.vpc_id
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.training.id
}


