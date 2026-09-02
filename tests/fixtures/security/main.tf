# Test fixture: a throwaway VPC + the security module. The security-group test
# applies this for real (security groups and a VPC are free) and destroys it
# afterwards.

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {}

variable "project" {
  type = string
}

resource "aws_vpc" "test" {
  cidr_block = "10.99.0.0/16"
  tags       = { Name = var.project }
}

module "security" {
  source  = "../../../terraform/modules/security"
  project = var.project
  vpc_id  = aws_vpc.test.id
}

output "alb_sg_id" {
  value = module.security.alb_sg_id
}

output "app_sg_id" {
  value = module.security.app_sg_id
}

output "db_sg_id" {
  value = module.security.db_sg_id
}
