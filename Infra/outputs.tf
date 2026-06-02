output "APIinvokeURL" {
    value = module.APIGateway.APIinvokeURL
}

output "cognito_domain" {
  value = module.Authentication.cognito_domain
}

output "cognito_client_id" {
  value = module.Authentication.cognito_client_id
}


output "redirect_uris" {
    value = module.Authentication.redirect_uris
    description = "List of allowed redirect URIs for the Cognito User Pool Client (used in Oauth flows)"
}

output "logout_uris" {
    value = module.Authentication.logout_uris
    description = "List of allowed Logout URIs for the Cognito User Pool Client (used in Oauth flows)"
}

output "distribution_id" {
  value = module.Cloudfront.distribution_id
  description = "Cloudfront distribution id for cache invalidation"
}

output "aws_region" {
  value = data.aws_region.current.id
  description = "AWS Region on which the application and infra is deployed"
}


output "cloudfront_domain_name" {
  value       = module.Cloudfront.cloudfront_domain_name
  description = "CloudFront domain name"
}

output "distribution_id" {
  value       = module.Cloudfront.distribution_id
  description = "CloudFront distribution id (use in CI for invalidations)"
}

output "acm_dns_validation" {
  value = module.Certificate.acm_dns_validation
  
}