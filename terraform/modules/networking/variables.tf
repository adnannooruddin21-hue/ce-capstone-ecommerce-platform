variable "project" {
  type = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

# "instance" or "gateway"
variable "nat_mode" {
  type    = string
  default = "instance"
}

variable "log_retention_days" {
  type    = number
  default = 3
}