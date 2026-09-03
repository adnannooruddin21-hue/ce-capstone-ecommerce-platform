# Monitoring — one CloudWatch dashboard (ce-capstone-overview), the
# CloudWatch-agent config parameter, the application log group, and an SNS topic
# with four alarms (ALB 5xx, unhealthy hosts, p95 latency, ASG CPU) delivered to
# email.

variable "project" { type = string }
variable "alb_arn_suffix" { type = string }
variable "tg_arn_suffix" { type = string }
variable "asg_name" { type = string }

locals {
  region = "eu-north-1"
  db_id  = "${var.project}-pg" # matches aws_db_instance.this.identifier in modules/data
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project}-overview"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6,
        properties = {
          title   = "ALB — requests & 5xx",
          region  = local.region,
          view    = "timeSeries",
          stacked = false,
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", label = "requests" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { stat = "Sum", label = "5xx" }]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6,
        properties = {
          title  = "ALB — target latency (p50 / p95 / p99)",
          region = local.region,
          view   = "timeSeries",
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p50", label = "p50" }],
            ["...", { stat = "p95", label = "p95" }],
            ["...", { stat = "p99", label = "p99" }]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6,
        properties = {
          title  = "ALB — host health",
          region = local.region,
          view   = "timeSeries",
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", var.tg_arn_suffix, "LoadBalancer", var.alb_arn_suffix, { stat = "Average", label = "healthy" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", var.tg_arn_suffix, "LoadBalancer", var.alb_arn_suffix, { stat = "Average", label = "unhealthy" }]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6,
        properties = {
          title  = "EC2 — CPU by ASG",
          region = local.region,
          view   = "timeSeries",
          yAxis  = { left = { min = 0, max = 100 } },
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name, { stat = "Average" }]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6,
        properties = {
          title  = "EC2 — memory & disk (CloudWatch agent)",
          region = local.region,
          view   = "timeSeries",
          yAxis  = { left = { min = 0, max = 100 } },
          metrics = [
            ["CWAgent", "mem_used_percent", "AutoScalingGroupName", var.asg_name, { stat = "Average", label = "mem %" }],
            ["CWAgent", "disk_used_percent", "AutoScalingGroupName", var.asg_name, { stat = "Average", label = "disk %" }]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 12, width = 12, height = 6,
        properties = {
          title  = "RDS — CPU / connections / freeable memory",
          region = local.region,
          view   = "timeSeries",
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", local.db_id, { stat = "Average", label = "CPU %" }],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", local.db_id, { stat = "Average", label = "connections", yAxis = "right" }],
            ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", local.db_id, { stat = "Average", label = "freeable mem (bytes)", yAxis = "right" }]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 18, width = 12, height = 6,
        properties = {
          title  = "App — orders & checkout failures (custom metrics)",
          region = local.region,
          view   = "timeSeries",
          metrics = [
            ["CloudCart/App", "OrdersPlaced", { stat = "Sum", label = "orders" }],
            ["CloudCart/App", "CheckoutFailures", { stat = "Sum", label = "checkout failures" }],
            ["CloudCart/App", "OrderRevenue", { stat = "Sum", label = "revenue", yAxis = "right" }]
          ]
        }
      }
    ]
  })
}

resource "aws_ssm_parameter" "cw_agent" {
  name  = "AmazonCloudWatch-${var.project}" # name matches CloudWatchAgentServerPolicy
  type  = "String"
  value = file("${path.module}/../../../monitoring/dashboards/cw-agent-config.json")
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ce-capstone/app"
  retention_in_days = 3
}

variable "alarm_email" { type = string }

variable "enable_alarm_formatter" {
  type    = bool
  default = true
}

# Not encrypted: CloudWatch Alarms cannot publish to a topic encrypted with the
# AWS-managed key alias/aws/sns (its key policy can't authorize cloudwatch.amazonaws.com),
# and a customer-managed KMS key is out of Free-Tier scope. This topic only carries
# CloudWatch alarm metadata (name, state, reason) — no secrets. See SECURITY.md.
resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

locals { actions = [aws_sns_topic.alerts.arn] }

# ------------------------------------------------------------------
# Alarm delivery
#
#   formatter OFF : alarms -> "alerts" -> email            (raw CloudWatch text)
#   formatter ON  : alarms -> "alerts" -> Lambda
#                          -> "alerts-email" -> email       (tidy, readable text)
#
# Two topics: SNS cannot rewrite a message in place, and a Lambda that
# published back to its own trigger topic would loop.
# ------------------------------------------------------------------

resource "aws_sns_topic_subscription" "email_raw" {
  count     = var.enable_alarm_formatter ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_sns_topic" "alerts_email" {
  count             = var.enable_alarm_formatter ? 1 : 0
  name              = "${var.project}-alerts-email"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "email_formatted" {
  count     = var.enable_alarm_formatter ? 1 : 0
  topic_arn = aws_sns_topic.alerts_email[0].arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

data "archive_file" "alarm_formatter" {
  count       = var.enable_alarm_formatter ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/src/alarm_formatter.py"
  output_path = "${path.module}/.alarm_formatter.zip"
}

resource "aws_iam_role" "alarm_formatter" {
  count = var.enable_alarm_formatter ? 1 : 0
  name  = "${var.project}-alarm-formatter"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "alarm_formatter" {
  count = var.enable_alarm_formatter ? 1 : 0
  name  = "publish-and-log"
  role  = aws_iam_role.alarm_formatter[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alerts_email[0].arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource = "*"
        Condition = {
          StringEquals = { "kms:ViaService" = "sns.${local.region}.amazonaws.com" }
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "alarm_formatter" {
  count             = var.enable_alarm_formatter ? 1 : 0
  name              = "/aws/lambda/${var.project}-alarm-formatter"
  retention_in_days = 3
}

resource "aws_lambda_function" "alarm_formatter" {
  count            = var.enable_alarm_formatter ? 1 : 0
  function_name    = "${var.project}-alarm-formatter"
  role             = aws_iam_role.alarm_formatter[0].arn
  runtime          = "python3.13"
  handler          = "alarm_formatter.lambda_handler"
  filename         = data.archive_file.alarm_formatter[0].output_path
  source_code_hash = data.archive_file.alarm_formatter[0].output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = { TARGET_TOPIC_ARN = aws_sns_topic.alerts_email[0].arn }
  }

  tracing_config { mode = "PassThrough" }

  depends_on = [aws_cloudwatch_log_group.alarm_formatter]
}

resource "aws_lambda_permission" "from_sns" {
  count         = var.enable_alarm_formatter ? 1 : 0
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.alarm_formatter[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

resource "aws_sns_topic_subscription" "to_lambda" {
  count      = var.enable_alarm_formatter ? 1 : 0
  topic_arn  = aws_sns_topic.alerts.arn
  protocol   = "lambda"
  endpoint   = aws_lambda_function.alarm_formatter[0].arn
  depends_on = [aws_lambda_permission.from_sns]
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project}-alb-5xx-high"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 5
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  alarm_actions       = local.actions
  ok_actions          = local.actions
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project}-unhealthy-hosts"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  dimensions          = { LoadBalancer = var.alb_arn_suffix, TargetGroup = var.tg_arn_suffix }
  alarm_actions       = local.actions
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  alarm_name          = "${var.project}-latency-p95-high"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 1.5
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  alarm_actions       = local.actions
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "asg_cpu" { # bonus 4th
  alarm_name          = "${var.project}-asg-cpu-high"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 75
  dimensions          = { AutoScalingGroupName = var.asg_name }
  alarm_actions       = local.actions
  treat_missing_data  = "notBreaching"
}

# Fires on any failed checkout in a 5-minute window (app custom metric).
resource "aws_cloudwatch_metric_alarm" "checkout_failures" {
  alarm_name          = "${var.project}-checkout-failures"
  namespace           = "CloudCart/App"
  metric_name         = "CheckoutFailures"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  alarm_actions       = local.actions
  treat_missing_data  = "notBreaching"
}

output "dashboard_name" { value = aws_cloudwatch_dashboard.main.dashboard_name }
