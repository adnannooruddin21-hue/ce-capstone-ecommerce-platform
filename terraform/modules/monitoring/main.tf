# Monitoring — the executive "ce-capstone-overview" CloudWatch dashboard
# (9 sections, traffic-light thresholds — see monitoring/dashboards/THRESHOLDS.md),
# the CloudWatch-agent config parameter, the application log group, and an SNS
# topic with five alarms (ALB 5xx, unhealthy hosts, p95 latency, ASG CPU,
# checkout failures) delivered to email via the alarm-formatter Lambda.

variable "project" { type = string }
variable "alb_arn_suffix" { type = string }
variable "tg_arn_suffix" { type = string }
variable "asg_name" { type = string }

locals {
  region = "eu-north-1"
  db_id  = "${var.project}-pg" # matches aws_db_instance.this.identifier in modules/data
  alb    = var.alb_arn_suffix
  tg     = var.tg_arn_suffix
  asg    = var.asg_name

  dash_alarms = [
    aws_cloudwatch_metric_alarm.alb_5xx.arn,
    aws_cloudwatch_metric_alarm.unhealthy_hosts.arn,
    aws_cloudwatch_metric_alarm.latency_p95.arn,
    aws_cloudwatch_metric_alarm.asg_cpu.arn,
    aws_cloudwatch_metric_alarm.checkout_failures.arn,
  ]

  # RDS allocated storage in bytes (20 GiB gp3) — used to derive "storage used %".
  db_storage_bytes = 20 * 1024 * 1024 * 1024
}

# ---------------------------------------------------------------------------
# ce-capstone-overview — an executive-first operations dashboard, ~20 widgets.
#
# Priority is readability over coverage: the first screen is 8 high-value
# widgets that answer "is my system healthy?" in seconds; everything below
# supports that story. Four sections:
#   01 Executive Overview -> is everything OK right now?
#   02 Application & Users -> how are users experiencing the app?
#   03 Infrastructure & Scaling -> are servers under pressure / adjusting?
#   04 Database Health -> is the database keeping up?
#
# Traffic-light thresholds (green / amber / red), documented in
# monitoring/dashboards/THRESHOLDS.md:
#   Availability %      >=99   / 95-99   / <95
#   Error rate %        <1     / 1-5     / >5
#   P95 response (ms)   <500   / 500-1500/ >1500   (1500 = the p95 alarm)
#   Server / DB CPU %   <60    / 60-85   / >85
#   Memory %            <70    / 70-90   / >90
#   DB storage used %   <75    / 75-90   / >90
#   Monthly spend USD   <1     / 1-10    / >10
#   System Health       0      / 1       / >=2  (count of the above at alarm level)
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project}-overview"
  dashboard_body = jsonencode({
    start          = "-PT3H"
    periodOverride = "inherit"
    widgets = [

      # ================= 01 · EXECUTIVE OVERVIEW ========================
      { type = "text", x = 0, y = 0, width = 24, height = 2, properties = {
        markdown = "# 🛒  CloudCart — Live Operations Dashboard\n## 01 · Executive Overview — is everything OK right now?  ·  Region **eu-north-1**  ·  Runs on the **AWS Free Tier**"
      } },

      { type = "metric", x = 0, y = 2, width = 8, height = 7, properties = {
        title = "Overall System Health", view = "gauge", region = local.region, period = 300,
        metrics = [
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.alb, { id = "s5", stat = "Sum", visible = false }],
          ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", local.tg, "LoadBalancer", local.alb, { id = "su", stat = "Maximum", visible = false }],
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb, { id = "sp", stat = "p95", visible = false }],
          ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", local.asg, { id = "sc", stat = "Average", visible = false }],
          ["CloudCart/App", "CheckoutFailures", { id = "sf", stat = "Sum", visible = false }],
          [{ expression = "IF(FILL(s5,0)>5,1,0)+IF(FILL(su,0)>0,1,0)+IF(FILL(sp,0)>1.5,1,0)+IF(FILL(sc,0)>75,1,0)+IF(FILL(sf,0)>0,1,0)", label = "Issues detected", id = "sh" }]
        ],
        yAxis = { left = { min = 0, max = 5 } },
        annotations = { horizontal = [
          { label = "Healthy", value = 0, color = "#2ca02c", fill = "above" },
          { label = "Attention", value = 1, color = "#ff7f0e", fill = "above" },
          { label = "Critical", value = 2, color = "#d62728", fill = "above" }
        ] }
      } },

      { type = "alarm", x = 8, y = 2, width = 16, height = 7, properties = {
        title  = "Live Alerts — green is good, red needs attention",
        alarms = local.dash_alarms
      } },

      { type = "metric", x = 0, y = 9, width = 4, height = 5, properties = {
        title = "Application Availability", view = "gauge", region = local.region, period = 300,
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb, { id = "aq", stat = "Sum", visible = false }],
          ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", local.alb, { id = "a2", stat = "Sum", visible = false }],
          [{ expression = "IF(FILL(aq,0)>0, 100*FILL(a2,0)/FILL(aq,0), 100)", label = "Availability %", id = "av" }]
        ],
        yAxis = { left = { min = 90, max = 100 } },
        annotations = { horizontal = [
          { label = "Critical", value = 90, color = "#d62728", fill = "above" },
          { label = "Attention", value = 95, color = "#ff7f0e", fill = "above" },
          { label = "Healthy", value = 99, color = "#2ca02c", fill = "above" }
        ] }
      } },

      { type = "metric", x = 4, y = 9, width = 4, height = 5, properties = {
        title = "Error Rate", view = "gauge", region = local.region, period = 300,
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb, { id = "eq", stat = "Sum", visible = false }],
          ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", local.alb, { id = "x4", stat = "Sum", visible = false }],
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", local.alb, { id = "x5", stat = "Sum", visible = false }],
          [{ expression = "IF(FILL(eq,0)>0, 100*(FILL(x4,0)+FILL(x5,0))/FILL(eq,0), 0)", label = "Error rate %", id = "er" }]
        ],
        yAxis = { left = { min = 0, max = 10 } },
        annotations = { horizontal = [
          { label = "Healthy", value = 0, color = "#2ca02c", fill = "above" },
          { label = "Attention", value = 1, color = "#ff7f0e", fill = "above" },
          { label = "Critical", value = 5, color = "#d62728", fill = "above" }
        ] }
      } },

      { type = "metric", x = 8, y = 9, width = 4, height = 5, properties = {
        title = "Response Time (P95)", view = "gauge", region = local.region, period = 300,
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb, { id = "rp", stat = "p95", visible = false }],
          [{ expression = "FILL(rp,0)*1000", label = "P95 (ms)", id = "rpm" }]
        ],
        yAxis = { left = { min = 0, max = 2000 } },
        annotations = { horizontal = [
          { label = "Healthy", value = 0, color = "#2ca02c", fill = "above" },
          { label = "Attention", value = 500, color = "#ff7f0e", fill = "above" },
          { label = "Critical", value = 1500, color = "#d62728", fill = "above" }
        ] }
      } },

      { type = "metric", x = 12, y = 9, width = 4, height = 5, properties = {
        title   = "Current Traffic", view = "singleValue", sparkline = true, region = local.region, period = 60, stat = "Sum",
        metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb, { label = "requests / min" }]]
      } },

      { type = "metric", x = 16, y = 9, width = 4, height = 5, properties = {
        title   = "Healthy Servers", view = "singleValue", sparkline = true, region = local.region, period = 300, stat = "Minimum",
        metrics = [["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", local.tg, "LoadBalancer", local.alb, { label = "of 3" }]]
      } },

      { type = "metric", x = 20, y = 9, width = 4, height = 5, properties = {
        title   = "Monthly Spend", view = "singleValue", sparkline = true, region = "us-east-1", period = 21600, stat = "Maximum",
        metrics = [["AWS/Billing", "EstimatedCharges", "Currency", "USD", { label = "USD (month-to-date)" }]]
      } },

      # ================= 02 · APPLICATION & USERS =======================
      { type = "text", x = 0, y = 14, width = 24, height = 1, properties = {
        markdown = "## 02 · Application & Users — how are users experiencing the app?"
      } },

      { type = "metric", x = 0, y = 15, width = 8, height = 6, properties = {
        title = "Orders & revenue (24 h)", view = "singleValue", region = local.region, period = 86400, stat = "Sum",
        metrics = [
          ["CloudCart/App", "OrdersPlaced", { label = "orders" }],
          ["CloudCart/App", "OrderRevenue", { label = "revenue (USD)" }]
        ]
      } },

      { type = "metric", x = 8, y = 15, width = 16, height = 6, properties = {
        title = "Response time — typical / slow / worst", view = "timeSeries", region = local.region, period = 60,
        yAxis = { left = { min = 0, showUnits = false, label = "seconds" } },
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", local.alb, { stat = "p50", label = "typical (p50)", color = "#2ca02c" }],
          ["...", { stat = "p95", label = "slow (p95)", color = "#ff7f0e" }],
          ["...", { stat = "p99", label = "worst (p99)", color = "#d62728" }]
        ],
        annotations = { horizontal = [{ label = "alert threshold", value = 1.5, color = "#d62728" }] }
      } },

      # ================= 03 · INFRASTRUCTURE & SCALING ==================
      { type = "text", x = 0, y = 21, width = 24, height = 2, properties = {
        markdown = "## 03 · Infrastructure & Scaling — are servers under pressure, and does it adjust automatically?\nTarget: keep CPU near **50%**. Load rises → more servers start (up to the ceiling); overnight → scale down. A server that stops responding is replaced automatically."
      } },

      { type = "metric", x = 0, y = 23, width = 6, height = 6, properties = {
        title   = "Server CPU Usage", view = "gauge", region = local.region, period = 300, stat = "Average",
        yAxis   = { left = { min = 0, max = 100 } },
        metrics = [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", local.asg, { label = "CPU %" }]],
        annotations = { horizontal = [
          { label = "comfortable", value = 0, color = "#2ca02c", fill = "above" },
          { label = "busy", value = 60, color = "#ff7f0e", fill = "above" },
          { label = "under pressure", value = 85, color = "#d62728", fill = "above" }
        ] }
      } },

      { type = "metric", x = 6, y = 23, width = 6, height = 6, properties = {
        title   = "Server Memory Usage", view = "gauge", region = local.region, period = 300, stat = "Average",
        yAxis   = { left = { min = 0, max = 100 } },
        metrics = [["CWAgent", "mem_used_percent", "AutoScalingGroupName", local.asg, { label = "memory %" }]],
        annotations = { horizontal = [
          { label = "ok", value = 0, color = "#2ca02c", fill = "above" },
          { label = "high", value = 70, color = "#ff7f0e", fill = "above" },
          { label = "critical", value = 90, color = "#d62728", fill = "above" }
        ] }
      } },

      { type = "metric", x = 12, y = 23, width = 12, height = 6, properties = {
        title = "Capacity vs demand — servers follow CPU, bounded by min / max", view = "timeSeries", region = local.region, period = 60,
        metrics = [
          ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", local.asg, { stat = "Average", label = "running servers", color = "#2ca02c" }],
          ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", local.asg, { stat = "Average", label = "target", color = "#1f77b4" }],
          ["AWS/AutoScaling", "GroupMinSize", "AutoScalingGroupName", local.asg, { stat = "Average", label = "minimum", color = "#7f7f7f" }],
          ["AWS/AutoScaling", "GroupMaxSize", "AutoScalingGroupName", local.asg, { stat = "Average", label = "maximum", color = "#7f7f7f" }],
          ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", local.asg, { stat = "Average", label = "CPU % (right axis)", yAxis = "right", color = "#9467bd" }]
        ],
        annotations = { horizontal = [{ label = "scale-out target (50% CPU)", value = 50, color = "#ff7f0e", yAxis = "right" }] }
      } },

      # ================= 04 · DATABASE HEALTH ===========================
      { type = "text", x = 0, y = 29, width = 24, height = 1, properties = {
        markdown = "## 04 · Database Health — is the database keeping up?"
      } },

      { type = "metric", x = 0, y = 30, width = 6, height = 6, properties = {
        title   = "Database CPU Usage", view = "gauge", region = local.region, period = 300, stat = "Average",
        yAxis   = { left = { min = 0, max = 100 } },
        metrics = [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", local.db_id, { label = "CPU %" }]],
        annotations = { horizontal = [
          { label = "comfortable", value = 0, color = "#2ca02c", fill = "above" },
          { label = "busy", value = 60, color = "#ff7f0e", fill = "above" },
          { label = "under pressure", value = 85, color = "#d62728", fill = "above" }
        ] }
      } },

      { type = "metric", x = 6, y = 30, width = 6, height = 6, properties = {
        title = "Database Storage Used", view = "gauge", region = local.region, period = 300,
        metrics = [
          ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", local.db_id, { id = "fs", stat = "Average", visible = false }],
          [{ expression = "100*(1 - fs/${local.db_storage_bytes})", label = "storage used %", id = "used" }]
        ],
        yAxis = { left = { min = 0, max = 100 } },
        annotations = { horizontal = [
          { label = "ok", value = 0, color = "#2ca02c", fill = "above" },
          { label = "high", value = 75, color = "#ff7f0e", fill = "above" },
          { label = "critical", value = 90, color = "#d62728", fill = "above" }
        ] }
      } },

      { type = "metric", x = 12, y = 30, width = 12, height = 6, properties = {
        title = "Database load — connections, memory, read/write latency", view = "timeSeries", region = local.region, period = 60,
        metrics = [
          ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", local.db_id, { stat = "Average", label = "connections", color = "#1f77b4" }],
          ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", local.db_id, { stat = "Average", label = "freeable memory (bytes)", yAxis = "right", color = "#2ca02c" }],
          ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", local.db_id, { stat = "Average", label = "read latency (s)", color = "#ff7f0e" }],
          ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", local.db_id, { stat = "Average", label = "write latency (s)", color = "#d62728" }]
        ]
      } }
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
