variable "db_proxy_id" {
    type = string
    description = "The id of the db proxy arn"

}

variable "region" {
  description = "AWS region Name"
  type        = string
}

variable "account_id" {
    description = "AWS Account Id"
    type = string
}

variable "vpc_id" {
    description = "VPC Id"
    type = string
}



variable "browse_cache" {
    type = string
    description = "ARN of the Browser Cache"
}

variable "active_user_lock_cache" {
    type = string
    description = "ARN of the Active User Lock Cache"

}

variable "seat_lock_cache" {
    type = string
    description = "ARN of the Seat Lock Cachre"
}

variable "user" {
    type = string
    description = "Cache User ARN"
}