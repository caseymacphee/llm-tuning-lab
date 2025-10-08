locals {
  create_resources = var.create_safety_resources && var.instance_id != null
}

# CloudWatch alarm for max runtime
resource "aws_cloudwatch_metric_alarm" "max_runtime" {
  count = local.create_resources ? 1 : 0

  alarm_name          = "${var.name}-training-max-runtime"
  alarm_description   = "Alert when training instance runs longer than ${var.max_runtime_hours} hours"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = var.max_runtime_hours * 3600
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = var.instance_id
  }

  alarm_actions = local.create_resources && var.alert_email != "" ? [aws_sns_topic.alerts[0].arn] : []

  tags = {
    Name        = "${var.name}-training-max-runtime"
    Environment = var.environment
  }
}

# EventBridge rule to auto-terminate after max runtime
resource "aws_cloudwatch_event_rule" "auto_terminate" {
  count = local.create_resources ? 1 : 0

  name                = "${var.name}-training-auto-terminate"
  description         = "Auto-terminate training instance after ${var.max_runtime_hours} hours"
  schedule_expression = "rate(${var.max_runtime_hours} hours)"

  tags = {
    Name        = "${var.name}-training-auto-terminate"
    Environment = var.environment
  }
}

# Lambda function for auto-termination
resource "aws_lambda_function" "auto_terminate" {
  count = local.create_resources ? 1 : 0

  filename         = data.archive_file.lambda[0].output_path
  function_name    = "${var.name}-training-auto-terminate"
  role             = aws_iam_role.lambda[0].arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.lambda[0].output_base64sha256
  runtime          = "python3.12"
  timeout          = 60

  environment {
    variables = {
      INSTANCE_ID = var.instance_id
    }
  }

  tags = {
    Name        = "${var.name}-training-auto-terminate"
    Environment = var.environment
  }
}

# Lambda function code
data "archive_file" "lambda" {
  count = local.create_resources ? 1 : 0

  type        = "zip"
  output_path = "${path.module}/lambda.zip"

  source {
    content  = <<-EOF
      import boto3
      import os
      from datetime import datetime, timedelta

      ec2 = boto3.client('ec2')

      def handler(event, context):
          instance_id = os.environ['INSTANCE_ID']
          max_hours = ${var.max_runtime_hours}
          
          # Get instance details
          response = ec2.describe_instances(InstanceIds=[instance_id])
          
          if not response['Reservations']:
              print(f"Instance {instance_id} not found")
              return
          
          instance = response['Reservations'][0]['Instances'][0]
          state = instance['State']['Name']
          
          if state != 'running':
              print(f"Instance {instance_id} is not running (state: {state})")
              return
          
          launch_time = instance['LaunchTime']
          runtime = datetime.now(launch_time.tzinfo) - launch_time
          runtime_hours = runtime.total_seconds() / 3600
          
          print(f"Instance {instance_id} has been running for {runtime_hours:.2f} hours")
          
          if runtime_hours >= max_hours:
              print(f"Terminating instance {instance_id} (exceeded max runtime of {max_hours} hours)")
              ec2.terminate_instances(InstanceIds=[instance_id])
              return {
                  'statusCode': 200,
                  'body': f'Terminated instance {instance_id}'
              }
          else:
              print(f"Instance {instance_id} within max runtime")
              return {
                  'statusCode': 200,
                  'body': f'Instance {instance_id} within max runtime'
              }
    EOF
    filename = "index.py"
  }
}

# IAM role for Lambda
resource "aws_iam_role" "lambda" {
  count = local.create_resources ? 1 : 0

  name = "${var.name}-training-auto-terminate-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.name}-training-auto-terminate-lambda"
    Environment = var.environment
  }
}

# Lambda policy
resource "aws_iam_role_policy" "lambda" {
  count = local.create_resources ? 1 : 0

  name = "${var.name}-training-auto-terminate-policy"
  role = aws_iam_role.lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:TerminateInstances"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# EventBridge target
resource "aws_cloudwatch_event_target" "lambda" {
  count = local.create_resources ? 1 : 0

  rule      = aws_cloudwatch_event_rule.auto_terminate[0].name
  target_id = "lambda"
  arn       = aws_lambda_function.auto_terminate[0].arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "eventbridge" {
  count = local.create_resources ? 1 : 0

  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_terminate[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.auto_terminate[0].arn
}

# SNS topic for alerts
resource "aws_sns_topic" "alerts" {
  count = local.create_resources && var.alert_email != "" ? 1 : 0

  name = "${var.name}-training-alerts"

  tags = {
    Name        = "${var.name}-training-alerts"
    Environment = var.environment
  }
}

# SNS subscription
resource "aws_sns_topic_subscription" "alerts" {
  count = local.create_resources && var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Cost alert (using AWS Budgets)
resource "aws_budgets_budget" "training" {
  count = local.create_resources && var.cost_alert_threshold > 0 ? 1 : 0

  name              = "${var.name}-training-budget"
  budget_type       = "COST"
  limit_amount      = tostring(var.cost_alert_threshold)
  limit_unit        = "USD"
  time_period_start = formatdate("YYYY-MM-01_00:00", timestamp())
  time_unit         = "MONTHLY"

  cost_filter {
    name = "TagKeyValue"
    values = [
      "user:Project$llm-tuning-lab"
    ]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.alert_email != "" ? [var.alert_email] : []
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.alert_email != "" ? [var.alert_email] : []
  }
}


