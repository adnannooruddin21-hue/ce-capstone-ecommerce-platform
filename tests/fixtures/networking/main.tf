# Test fixture: instantiate the networking module on its own so Terratest can
# plan it in isolation. Nothing here is applied by the plan-only test.

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

module "networking" {
  source  = "../../../terraform/modules/networking"
  project = var.project
}

output "vpc_cidr" {
  value = module.networking.vpc_cidr
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.networking.private_subnet_ids
}
