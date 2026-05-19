
variable "vpc_name" {
  type    = string
  default = "demo_vpc"
}

variable "vpc_cidr" {
  type    = string
  #default = "10.0.0.0/16"
}



variable "region" {
  description = "AWS region Name"
  type        = string
}



variable "availability_zones" {
  description = "list of availbility zones"
  type = list(string)
}


variable "common_tags" {
  description = "Common tags for resources"
  type        = map(string)
} 



variable "private_subnets" {
  default = {
    "private_subnet_1" = 0
    "private_subnet_2" = 1
    "private_subnet_3" = 2
  }
}


locals {
  private_subnet_ids = [for s in aws_subnet.private_subnets : s.id]
  # or: values(aws_subnet.private)[*].id
}



variable "referenced_security_group_id" {
  type = string
  description = "Referncing the lambda security group"
}