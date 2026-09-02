# Data — RDS PostgreSQL (single-AZ db.t3.micro, storage-encrypted, not publicly
# accessible) in a private DB subnet group. The master password and the Flask
# session secret are generated here and stored as SSM SecureString parameters
# under /ce-capstone/.

variable "project" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "db_sg_id" {
  type = string
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-db"
  subnet_ids = var.private_subnet_ids
}

resource "aws_db_instance" "this" {
  identifier              = "${var.project}-pg"
  engine                  = "postgres"
  engine_version          = "16"
  instance_class          = var.instance_class
  allocated_storage       = 20
  storage_type            = "gp3"
  storage_encrypted       = true
  db_name                 = "cloudcart"
  username                = "appuser"
  password                = random_password.db.result
  db_subnet_group_name    = aws_db_subnet_group.this.name
  vpc_security_group_ids  = [var.db_sg_id]
  multi_az                = false
  publicly_accessible     = false
  skip_final_snapshot     = true
  backup_retention_period = 1
  apply_immediately       = true
}

resource "aws_ssm_parameter" "db_host" {
  name  = "/${var.project}/db/host"
  type  = "String"
  value = aws_db_instance.this.address
}
resource "aws_ssm_parameter" "db_name" {
  name  = "/${var.project}/db/name"
  type  = "String"
  value = aws_db_instance.this.db_name
}
resource "aws_ssm_parameter" "db_user" {
  name  = "/${var.project}/db/user"
  type  = "String"
  value = aws_db_instance.this.username
}
resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project}/db/password"
  type  = "SecureString"
  value = random_password.db.result
}

# Flask session secret for the CloudCart app
resource "random_password" "app_secret" {
  length  = 40
  special = false
}
resource "aws_ssm_parameter" "app_secret" {
  name  = "/${var.project}/app/secret_key"
  type  = "SecureString"
  value = random_password.app_secret.result
}

output "db_endpoint" { value = aws_db_instance.this.address }