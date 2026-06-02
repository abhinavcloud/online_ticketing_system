
output "acm_dns_validation" {
  value = aws_acm_certificate.online_ticket_system_cert.domain_validation_options
}

output "acm_cert" {
    value = aws_acm_certificate.cfonline_ticket_system_certcert.arn
}
