output "training_bucket_name" {
  description = "Name of the training data S3 bucket"
  value       = aws_s3_bucket.training_data.bucket
}

output "training_bucket_arn" {
  description = "ARN of the training data S3 bucket"
  value       = aws_s3_bucket.training_data.arn
}

output "outputs_bucket_name" {
  description = "Name of the outputs S3 bucket"
  value       = aws_s3_bucket.outputs.bucket
}

output "outputs_bucket_arn" {
  description = "ARN of the outputs S3 bucket"
  value       = aws_s3_bucket.outputs.arn
}


