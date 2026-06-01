output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.site.domain_name
  description = "CloudFront domain name"
}

output "distribution_id" {
  value       = aws_cloudfront_distribution.site.id
  description = "CloudFront distribution id (use in CI for invalidations)"
}


