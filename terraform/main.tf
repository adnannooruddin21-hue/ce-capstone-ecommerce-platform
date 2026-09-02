module "networking" {
  source   = "./modules/networking"
  project  = var.project
  nat_mode = "instance"
}

module "security" {
  source   = "./modules/security"
  project  = var.project
  vpc_id   = module.networking.vpc_id
  app_port = var.app_port
}

module "compute" {
  source             = "./modules/compute"
  project            = var.project
  region             = var.region
  vpc_id             = module.networking.vpc_id
  public_subnet_ids  = module.networking.public_subnet_ids
  private_subnet_ids = module.networking.private_subnet_ids
  alb_sg_id          = module.security.alb_sg_id
  app_sg_id          = module.security.app_sg_id
  instance_type      = var.instance_type
  app_port           = var.app_port
  app_version        = "2.0.0"
}

module "monitoring" {
  source         = "./modules/monitoring"
  project        = var.project
  alb_arn_suffix = module.compute.alb_arn_suffix
  tg_arn_suffix  = module.compute.tg_arn_suffix
  asg_name       = module.compute.asg_name
  alarm_email    = var.alarm_email
}
module "data" {
  source             = "./modules/data"
  project            = var.project
  private_subnet_ids = module.networking.private_subnet_ids
  db_sg_id           = module.security.db_sg_id
}

module "governance" {
  source           = "./modules/governance"
  project          = var.project
  recorder_enabled = false # evidence captured 2026-09-02; recorder stopped to stay in Free Tier
}
