
output "acm_dns_validation_tld" {
  value = aws_acm_certificate.online_ticket_system_cert_tld.domain_validation_options
}


output "acm_dns_validation_sub" {
  value = aws_acm_certificate.online_ticket_system_cert_sub.domain_validation_options
}


output "acm_cert_tld" {
    value = aws_acm_certificate.online_ticket_system_cert_tld.arn
}


output "acm_cert_sub" {
    value = aws_acm_certificate.online_ticket_system_cert_sub.arn
}
