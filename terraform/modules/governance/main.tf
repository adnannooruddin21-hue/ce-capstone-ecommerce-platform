# Governance — an AWS Config recorder scoped to a handful of resource types
# (behind a recorder_enabled toggle) with its own delivery S3 bucket, plus the
# managed compliance rules.

variable "project" { type = string }
variable "recorder_enabled" {
  type    = bool
  default = true
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "config" {
  bucket        = "${var.project}-config-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}
resource "aws_s3_bucket_public_access_block" "config" {
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# AWS Config's delivery channel writes as the config.amazonaws.com service
# principal, which needs an explicit bucket policy (not just the role policy).
resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSConfigBucketPermissionsCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource  = aws_s3_bucket.config.arn
      },
      {
        Sid       = "AWSConfigBucketDelivery"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.config.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      }
    ]
  })
}

data "aws_iam_policy_document" "config_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "config" {
  name               = "${var.project}-config"
  assume_role_policy = data.aws_iam_policy_document.config_assume.json
}
resource "aws_iam_role_policy_attachment" "config_managed" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}
resource "aws_iam_role_policy" "config_s3" {
  role = aws_iam_role.config.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetBucketAcl"]
      Resource = [aws_s3_bucket.config.arn, "${aws_s3_bucket.config.arn}/*"]
    }]
  })
}

resource "aws_config_configuration_recorder" "this" {
  name     = var.project
  role_arn = aws_iam_role.config.arn
  recording_group {
    all_supported = false
    resource_types = [
      "AWS::EC2::Instance", "AWS::EC2::SecurityGroup", "AWS::EC2::VPC",
      "AWS::S3::Bucket", "AWS::IAM::Role", "AWS::IAM::Policy",
      "AWS::RDS::DBInstance",
    ]
  }
}
resource "aws_config_delivery_channel" "this" {
  name           = var.project
  s3_bucket_name = aws_s3_bucket.config.bucket
  depends_on = [
    aws_config_configuration_recorder.this,
    aws_s3_bucket_policy.config,
  ]
}
resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = var.recorder_enabled
  depends_on = [aws_config_delivery_channel.this]
}

locals {
  rules = {
    "restricted-ssh"                   = "INCOMING_SSH_DISABLED"
    "s3-bucket-public-read-prohibited" = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
    "encrypted-volumes"                = "ENCRYPTED_VOLUMES"
    "rds-storage-encrypted"            = "RDS_STORAGE_ENCRYPTED"
    "vpc-flow-logs-enabled"            = "VPC_FLOW_LOGS_ENABLED"
  }
}
resource "aws_config_config_rule" "managed" {
  for_each = local.rules
  name     = each.key
  source {
    owner             = "AWS"
    source_identifier = each.value
  }
  depends_on = [aws_config_configuration_recorder_status.this]
}
