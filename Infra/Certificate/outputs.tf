
output "acm_dns_validation" {
  value = aws_acm_certificate.cf_cert.domain_validation_options
}

output "acm_cert" {
    value = aws_acm_certificate.cf_cert.arn
}
