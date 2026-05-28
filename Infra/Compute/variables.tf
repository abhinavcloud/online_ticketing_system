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

variable "security_group_id" {
    type = string 
    description = "Lambda security group id"
}

variable "db_proxy_security_group" {
    type = string
    description = "RDS Proxy Security Group"
}

variable "elasticache_security_group" {
    type = string
    description = " Elasticache Security Group"
}

variable "subnet_group" {
    description = "list of subnet groups"
    type = list(string)
}


variable "db_proxy_endpoint" {
  type        = string
  description = "RDS Proxy endpoint hostname"
}


variable "db_port" {
  type        = number
  default     = 5432
}



variable "db_name" {
  type        = string
}


variable "db_user" {
  type        = string
  description = "IAM-enabled DB user Lambda will connect as (e.g., app_user)"
}



variable "browse_cache_endpoint" {
  type        = string
  description = "ElastiCache serverless endpoint hostname for browse cache"
}



variable "browse_cache_port" {
  type        = number
  default     = 6379
}



variable "browse_cache_name" {
  type        = string
  description = "Serverless cache name (e.g., browse-cache). Needed for IAM token signing"
}



variable "elasticache_user_id" {
  type        = string
  description = "ElastiCache IAM-enabled user id (must match username)"
}



variable "browse_cache_ttl_seconds" {
  type        = number
  default     = 30
}



variable "active_users_cache_endpoint" { type = string }
variable "active_users_cache_port"     { type = number }
variable "active_users_cache_name"     { type = string }
variable "vpc_endpoint_security_group" { type = string }
variable "seat_lock_cache_endpoint" { type = string }
variable "seat_lock_cache_port" {type = number}
variable "seat_lock_cache_name" {type = string}
variable "notification_topic_arn" { type = string}
