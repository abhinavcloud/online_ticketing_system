
provider "aws" {
  alias  = "use1"
  region = "us-east-1"
}



resource "aws_acm_certificate" "online_ticket_system_cert" {
  provider          = aws.use1
  domain_name       = var.root_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}



