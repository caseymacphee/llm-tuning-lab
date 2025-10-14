locals {
  create_networking = var.create_vpc
  vpc_id            = local.create_networking ? aws_vpc.training[0].id : var.vpc_id
  subnet_id         = local.create_networking ? aws_subnet.training[0].id : var.subnet_id
  
  tags = {
    Name        = "${var.name}-training"
    Environment = var.environment
    Purpose     = "ml-training"
  }
}

# Optional VPC for training (if create_vpc is true)
resource "aws_vpc" "training" {
  count = local.create_networking ? 1 : 0
  
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, {
    Name = "${var.name}-training-vpc"
  })
}

resource "aws_internet_gateway" "training" {
  count  = local.create_networking ? 1 : 0
  vpc_id = aws_vpc.training[0].id

  tags = merge(local.tags, {
    Name = "${var.name}-training-igw"
  })
}

resource "aws_subnet" "training" {
  count = local.create_networking ? 1 : 0
  
  vpc_id                  = aws_vpc.training[0].id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${var.name}-training-subnet"
  })
}

resource "aws_route_table" "training" {
  count  = local.create_networking ? 1 : 0
  vpc_id = aws_vpc.training[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.training[0].id
  }

  tags = merge(local.tags, {
    Name = "${var.name}-training-rt"
  })
}

resource "aws_route_table_association" "training" {
  count          = local.create_networking ? 1 : 0
  subnet_id      = aws_subnet.training[0].id
  route_table_id = aws_route_table.training[0].id
}

# Security Group
resource "aws_security_group" "training" {
  name        = "${var.name}-training-sg"
  description = "Security group for ML training instance"
  vpc_id      = local.vpc_id

  # Egress: Allow all outbound (for pip, git, S3, ECR, etc.)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  # Optional SSH ingress (only if key_name is provided)
  dynamic "ingress" {
    for_each = var.key_name != null ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]  # Restrict this in production
      description = "SSH access"
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-training-sg"
  })
}

# IAM Role for EC2
resource "aws_iam_role" "training" {
  name = "${var.name}-training-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.tags
}

# Attach SSM policy for Systems Manager access
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.training.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach CloudWatch policy for logging
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.training.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Custom policy for S3 and ECR access
resource "aws_iam_role_policy" "training" {
  name = "${var.name}-training-policy"
  role = aws_iam_role.training.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.training_bucket}",
          "arn:aws:s3:::${var.training_bucket}/*",
          "arn:aws:s3:::${var.outputs_bucket}",
          "arn:aws:s3:::${var.outputs_bucket}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/aws/ec2/training/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:TerminateInstances"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/Name" = "${var.name}-training"
          }
        }
      }
    ]
  })
}

# Instance profile
resource "aws_iam_instance_profile" "training" {
  name = "${var.name}-training-profile"
  role = aws_iam_role.training.name

  tags = local.tags
}

# Get latest Deep Learning AMI
data "aws_ami" "deep_learning" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04)*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# Get current region
data "aws_region" "current" {}

# Training EC2 instance
resource "aws_instance" "training" {
  count = var.create_instance ? 1 : 0

  ami           = data.aws_ami.deep_learning.id
  instance_type = var.instance_type
  key_name      = var.key_name

  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.training.id]
  iam_instance_profile        = aws_iam_instance_profile.training.name
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.volume_size
    delete_on_termination = true
    encrypted             = true
  }

  user_data_base64 = base64encode(templatefile("${path.module}/user-data.sh", {
    ecr_repository_url = var.ecr_repository_url
    docker_image_tag   = var.docker_image_tag
    training_bucket    = var.training_bucket
    outputs_bucket     = var.outputs_bucket
    training_command   = var.training_command
    auto_shutdown      = var.auto_shutdown ? "true" : "false"
    region             = data.aws_region.current.id
  }))

  # Spot instance request
  instance_market_options {
    market_type = var.use_spot ? "spot" : null

    dynamic "spot_options" {
      for_each = var.use_spot ? [1] : []
      content {
        max_price                      = var.spot_price != "" ? var.spot_price : null
        spot_instance_type             = "one-time"
        instance_interruption_behavior = "terminate"
      }
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # Enforce IMDSv2
    http_put_response_hop_limit = 1
  }

  tags = merge(local.tags, {
    Name = "${var.name}-training"
  })

  volume_tags = merge(local.tags, {
    Name = "${var.name}-training-volume"
  })

  lifecycle {
    ignore_changes = [ami]  # Don't replace instance when AMI updates
  }
}


