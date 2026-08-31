terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

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
  description = "owner/repo that may assume the deploy role"
  type        = string
}

data "aws_caller_identity" "current" {}

# ---- Remote state bucket ----
resource "aws_s3_bucket" "tfstate" {
  bucket = "ce-capstone-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
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
    filter {} # applies to all objects; required by provider v5
    noncurrent_version_expiration { noncurrent_days = 30 }
  }
}

# ---- Lock table ----
resource "aws_dynamodb_table" "tflock" {
  name         = "ce-capstone-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

# ---- GitHub Actions OIDC ----
# The account-level provider is shared; look it up, do not manage it here.
# If your account does NOT already have it, create it once in the console or with
#   aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com --client-id-list sts.amazonaws.com
data "aws_iam_openid_connect_provider" "gha" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "gha_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.gha.arn]
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

output "state_bucket" { value = aws_s3_bucket.tfstate.id }
output "lock_table" { value = aws_dynamodb_table.tflock.name }
output "gha_role_arn" { value = aws_iam_role.gha_deploy.arn }
