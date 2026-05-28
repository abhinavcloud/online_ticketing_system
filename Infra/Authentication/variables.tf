variable "client_id" {
  description = "Cognito User Pool App Client ID for authentication"
  type        = string
}

variable "client_secret" {
  description = "Cognito User Pool App Client Secret for authentication"
  type        = string
}

variable "app_name" {
  description = "Application name for resource naming"
  type        = string
}

variable "root_domain" {
  description = "Root domain for the application (used in Cognito callback URLs)"
  type        = string
}


