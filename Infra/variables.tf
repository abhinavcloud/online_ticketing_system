variable "vpc_cidr" {
  type = string
  default = "10.1.0.0/16"

}



variable "Environment" {
  type = string
  default = "demo"
}

variable "Application" {
  type = string
  default = "online-ticket-system"
}

locals {
  common_tags = {
    Environment = var.Environment
    Application = var.Application
  }
}

variable "account_id" {
    description = "AWS Account Id"
    type = string

}

variable "master_username" {
    description = "Aurora DB Master Username"
    type = string
}

variable "master_password" {
    description = "Aurora DB Master Password"
    type = string
}


variable "app_db_user" {
  type        = string
  description = "IAM-enabled Postgres user for application lambdas"
  default     = "app_user"
}
