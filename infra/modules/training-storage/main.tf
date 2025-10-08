# S3 bucket for training data
resource "aws_s3_bucket" "training_data" {
  bucket = "${var.name}-training-data-${var.environment}"

  tags = {
    Name        = "${var.name}-training-data"
    Environment = var.environment
    Purpose     = "ml-training-input"
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "training_data" {
  bucket = aws_s3_bucket.training_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning for training data
resource "aws_s3_bucket_versioning" "training_data" {
  bucket = aws_s3_bucket.training_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle policy for training data
resource "aws_s3_bucket_lifecycle_configuration" "training_data" {
  bucket = aws_s3_bucket.training_data.id

  rule {
    id     = "archive-old-data"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# S3 bucket for training outputs
resource "aws_s3_bucket" "outputs" {
  bucket = "${var.name}-outputs-${var.environment}"

  tags = {
    Name        = "${var.name}-outputs"
    Environment = var.environment
    Purpose     = "ml-training-output"
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "outputs" {
  bucket = aws_s3_bucket.outputs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning for outputs
resource "aws_s3_bucket_versioning" "outputs" {
  bucket = aws_s3_bucket.outputs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle policy for outputs
resource "aws_s3_bucket_lifecycle_configuration" "outputs" {
  bucket = aws_s3_bucket.outputs.id

  rule {
    id     = "intelligent-tiering"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }

    transition {
      days          = 180
      storage_class = "GLACIER"
    }
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "training_data" {
  bucket = aws_s3_bucket.training_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "outputs" {
  bucket = aws_s3_bucket.outputs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


