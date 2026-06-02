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
    sensitive = true
}

variable "master_password" {
    description = "Aurora DB Master Password"
    type = string
    sensitive = true
}


variable "app_db_user" {
  type        = string
  description = "IAM-enabled Postgres user for application lambdas"
  
}

variable "notification_email" {
  description = "Email address to receive notifications (must be subscribed to the SNS topic)"
  type        = string
  default    = "abhinav@abhinav-cloud.com"
}

variable "app_name" {
  description = "Application name for resource naming"
  type        = string
  default     = "online-ticket-system"
}

variable "root_domain" {
  description = "Root domain for the application (used in Cognito callback URLs)"
  type        = string
}


variable "client_id" {
  description = "Cognito User Pool App Client ID for authentication"
  type        = string
 }

variable "client_secret" {
  description = "Cognito User Pool App Client Secret for authentication"
  type        = string
  sensitive = true
}


variable "enable_custom_domain" {
  description = "Enable custom domain + ACM cert on CloudFront"
  type        = bool
  default     = false
}