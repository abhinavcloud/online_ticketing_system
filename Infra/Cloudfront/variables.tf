variable "bucket_name" {
  description = "S3 bucket name for the website"
  type        = string
}

variable "bucket_arn" {
  description = "ARN of the S3 bucket"
  type        = string
}

variable "bucket_regional_domain_name" {
    description = "Regional domain name"
    type = string
}

variable "base_url" {
    description = "Base URL for API Gateway stage."
    type = string
}

variable "root_domain" {
  type = string
  description = "Public domain name"
}



variable "enable_custom_domain" {
  description = "Enable custom domain + ACM cert on CloudFront"
  type        = bool
  default     = false
}

variable "acm_cert" {
  description = "Domain Certificate"
  type = string
}
