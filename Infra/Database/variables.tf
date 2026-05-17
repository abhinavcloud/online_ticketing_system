variable "availability_zones" {
  description = "list of availbility zones"
  type = list(string)
}

variable "subnet_group" {
    description = "list of subnet groups"
    type = list(string)
}

variable "vpc_id" {
    description = "VPC Id"
    type = string
}

variable "region" {
  description = "AWS region Name"
  type        = string
}

variable "account_id" {
    description = "AWS Account Id"
    type = string
}