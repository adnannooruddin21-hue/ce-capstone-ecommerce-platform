# Bootstrap — one-time remote-state setup, applied with a local backend before
# the main stack: the S3 state bucket, the DynamoDB lock table, and the GitHub
# OIDC provider + deploy role (see ADR 0001 for why CI ultimately uses an IAM
# user instead).

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}

# Bootstrap stack: remote state backend + GitHub Actions deploy role.
# Applied once with LOCAL state (no backend block here).
provider "aws" {
  region = "eu-north-1"
  default_tags {
    tags = {
      Project   = "ce-capstone-ecommerce"
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}

variable "github_repo" {
  description = "owner/repo allowed to assume the deploy role"
  type        = string
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Remote state bucket + lock table
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = "ce-capstone-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    id     = "expire-noncurrent"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_dynamodb_table" "tflock" {
  name         = "ce-capstone-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC provider + deploy role
# ---------------------------------------------------------------------------
data "tls_certificate" "gha" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "gha" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.gha.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "gha_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.gha.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:job_workflow_ref"
      values   = ["${var.github_repo}/.github/workflows/*"]
    }
  }
}

resource "aws_iam_role" "gha_deploy" {
  name               = "ce-capstone-gha-deploy"
  assume_role_policy = data.aws_iam_policy_document.gha_assume.json
}

# Broad for the capstone timeline; tighten on Tuesday's security pass.
resource "aws_iam_role_policy_attachment" "gha_admin" {
  role       = aws_iam_role.gha_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ---------------------------------------------------------------------------
output "state_bucket" {
  value = aws_s3_bucket.tfstate.id
}

output "lock_table" {
  value = aws_dynamodb_table.tflock.name
}

output "gha_role_arn" {
  value = aws_iam_role.gha_deploy.arn
}
