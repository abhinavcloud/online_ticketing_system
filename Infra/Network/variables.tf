#Created by: Abhinav Kumar (abhinav@abhinav-cloud.com)
#Version 1.0

variable "vpc_name" {
  type    = string
  default = "demo_vpc"
}

variable "vpc_cidr" {
  type    = string
  #default = "10.0.0.0/16"
}



variable "Region" {
  description = "AWS Region Name"
  type        = string
}

variable az_name_tag {
  description = "Comma-separated list of Availability Zones"
  type        = string
}


variable common_tags {
  description = "Common tags for resources"
  type        = map(string)
} 
