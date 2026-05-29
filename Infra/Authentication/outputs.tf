data "aws_region" "current" {}

output "user_pool_arn" {
    value = aws_cognito_user_pool.google.arn
    description = "ARN of the Cognito User Pool for Google Sign In"
}

output "cognito_domain" {
    value = aws_cognito_user_pool_domain.google_domain.domain
    description = "Cognito User Pool Domain for Google Sign In (used in Hosted UI and as the application domain for Oauth)"
}

output "cognito_client_id" {
    value = aws_cognito_user_pool_client.google_client.id
    description = "Cognito User Pool Client ID for Google Sign In"
}

output "redirect_uris" {
    value = aws_cognito_user_pool_client.google_client.callback_urls
    description = "List of allowed redirect URIs for the Cognito User Pool Client (used in Oauth flows)"
}

output "google_authorized_redirect_uri" {
    value = "https://${aws_cognito_user_pool_domain.google_domain.domain}.auth.${data.aws_region.current.region}.amazoncognito.com/oauth2/idpresponse"
    description = "The redirect URI to be registered with Google for Oauth (Cognito Hosted UI callback URL for Google Sign In)"
}
