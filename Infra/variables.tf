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
    default = "1234"
}