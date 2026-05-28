# Creating the Identity Provider with Cognito for Google
resource "aws_cognito_identity_provider" "google_provider" {
  user_pool_id  = aws_cognito_user_pool.google.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    authorize_scopes = "email"
    client_id        = var.client_id
    client_secret    = var.client_secret
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
  }
}


# Creating Cognito User Pool and User Pool Client for Google Sign In
resource "aws_cognito_user_pool" "google" {
  name                     = "google-pool"
  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_client" "google_client" {
  name                                 = "google_client"
  user_pool_id                         = aws_cognito_user_pool.google.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "openid"]

  # Callback URLs for Hosted UI (after successful authentication)
  callback_urls                        = ["https://${var.root_domain}", "http://localhost:3000"]
  # Logout URLs for Hosted UI (after sign out)
  logout_urls                          = ["https://${var.root_domain}", "http://localhost:3000"]
  

  supported_identity_providers         = ["Google"]

  depends_on = [aws_cognito_identity_provider.google_provider]
}


# Creating a Cognito User Pool Domain for Hosted UI which is used for Google Sign In. 
# This is the application domain registered with Google for Oauth.
resource "aws_cognito_user_pool_domain" "google_domain" {
  domain       = "${var.app_name}-auth"  # must be globally unique
  user_pool_id = aws_cognito_user_pool.google.id

  depends_on = [ aws_cognito_user_pool.google ]
}
