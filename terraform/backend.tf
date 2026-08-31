terraform {
  backend "s3" {
    bucket         = "ce-capstone-tfstate-128529977749"
    key            = "prod/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "ce-capstone-tflock"
    encrypt        = true
  }
}