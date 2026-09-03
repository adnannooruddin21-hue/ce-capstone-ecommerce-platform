# Compute — launch template (Amazon Linux 2023, IMDSv2, encrypted root), the
# ALB + target group, the Auto Scaling Group with its target-tracking policy and
# night/morning schedules, and delivery of the zipped Flask app via a private S3
# bucket keyed by content hash.

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---------- IAM instance role ----------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.project}-app-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project}-app-instance"
  role = aws_iam_role.app.name
}

# ---------- Application bundle (zip app/src -> S3, instances pull it) ----------
data "archive_file" "app" {
  type        = "zip"
  source_dir  = "${path.module}/../../../app/src"
  output_path = "${path.module}/.app_bundle.zip"
}

resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = "${var.project}-artifacts-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_object" "app" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "app-${data.archive_file.app.output_md5}.zip"
  source = data.archive_file.app.output_path
  etag   = data.archive_file.app.output_md5
}

resource "aws_iam_role_policy" "app_artifacts_read" {
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.artifacts.arn}/*"
    }]
  })
}

# ---------- Account-level EC2 metadata defaults ----------
resource "aws_ec2_instance_metadata_defaults" "secure" {
  http_tokens            = "required"
  instance_metadata_tags = "disabled"
}

# ---------- Launch template ----------
resource "aws_launch_template" "app" {
  name_prefix   = "${var.project}-app-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = var.instance_type

  iam_instance_profile { name = aws_iam_instance_profile.app.name }
  vpc_security_group_ids = [var.app_sg_id]

  metadata_options {
    http_tokens            = "required" # IMDSv2 only
    http_endpoint          = "enabled"
    instance_metadata_tags = "disabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 8
      volume_type = "gp3"
      encrypted   = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    region           = var.region
    artifacts_bucket = aws_s3_bucket.artifacts.id
    app_key          = aws_s3_object.app.key
    app_port         = var.app_port
    app_version      = var.app_version
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project}-app" }
  }
}

# ---------- ALB + target group ----------
resource "aws_lb" "app" {
  name                       = "${var.project}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [var.alb_sg_id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "app" {
  name     = "${var.project}-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ---------- Auto Scaling Group ----------
resource "aws_autoscaling_group" "app" {
  name                      = "${var.project}-asg"
  desired_capacity          = var.desired_capacity
  min_size                  = var.min_size
  max_size                  = var.max_size
  vpc_zone_identifier       = var.private_subnet_ids
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 120

  launch_template {
    id = aws_launch_template.app.id
    # Concrete version (not "$Latest") so a new launch-template version produces a
    # real diff on this ASG, which is what triggers the rolling instance_refresh.
    version = aws_launch_template.app.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences { min_healthy_percentage = 50 }
  }

  # Publish group capacity metrics (running / desired / min / max / pending /
  # terminating) so the dashboard can tell the auto-scaling story. Free.
  metrics_granularity = "1Minute"
  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]

  tag {
    key                 = "Name"
    value               = "${var.project}-app"
    propagate_at_launch = true
  }
}

variable "region" { type = string }
data "aws_caller_identity" "current" {}

# ---------- Account-level S3 Public Access Block ----------
resource "aws_s3_account_public_access_block" "account" {
  account_id = data.aws_caller_identity.current.account_id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_iam_role_policy" "app_ssm_read" {
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/*"
      },
      {
        Effect    = "Allow"
        Action    = ["kms:Decrypt"]
        Resource  = "*"
        Condition = { StringEquals = { "kms:ViaService" = "ssm.${var.region}.amazonaws.com" } }
      }
    ]
  })
}

# The app publishes business metrics (orders, revenue, checkout failures).
# PutMetricData has no resource-level permissions, so it is scoped by namespace.
resource "aws_iam_role_policy" "app_metrics_write" {
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["cloudwatch:PutMetricData"]
      Resource  = "*"
      Condition = { StringEquals = { "cloudwatch:namespace" = "CloudCart/App" } }
    }]
  })
}

resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "${var.project}-cpu-target-50"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification { predefined_metric_type = "ASGAverageCPUUtilization" }
    target_value = 50
  }
}

resource "aws_autoscaling_schedule" "night_in" {
  scheduled_action_name  = "${var.project}-night-in"
  autoscaling_group_name = aws_autoscaling_group.app.name
  min_size               = 1
  max_size               = 4
  desired_capacity       = 1
  recurrence             = "0 22 * * *" # 22:00 UTC daily
}

resource "aws_autoscaling_schedule" "morning_out" {
  scheduled_action_name  = "${var.project}-morning-out"
  autoscaling_group_name = aws_autoscaling_group.app.name
  min_size               = 3
  max_size               = 4
  desired_capacity       = 3
  recurrence             = "0 6 * * *"
}
