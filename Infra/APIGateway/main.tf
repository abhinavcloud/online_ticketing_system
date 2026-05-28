# Create an API Gateway REST API to expose the lambda functions
resource "aws_api_gateway_rest_api" "ticketing_api" {
  name        = "TicketingAPI"
  description = "API Gateway for the Ticketing System"
  tags = {
    Application = "TicketingSystem"
    Type = "API_Gateway"
  }
}

# --------------------------------------------------------------------------------

# Get /v1/location resource, method and integration

resource "aws_api_gateway_resource" "location_resource" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  parent_id   = aws_api_gateway_rest_api.ticketing_api.root_resource_id
  path_part   = "/v1/location"
}

resource "aws_api_gateway_method" "location_get_method" {
  rest_api_id   = aws_api_gateway_rest_api.ticketing_api.id
  resource_id   = aws_api_gateway_resource.location_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "location_get_integration" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  resource_id = aws_api_gateway_resource.location_resource.id
  http_method = aws_api_gateway_method.location_get_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.browse_service_arn
}

# --------------------------------------------------------------------------------

# Get /v1/venue resource, method and integration
resource "aws_api_gateway_resource" "venue_resource" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  parent_id   = aws_api_gateway_rest_api.ticketing_api.root_resource_id
  path_part   = "/v1/venue"
}

resource "aws_api_gateway_method" "venue_get_method" {
  rest_api_id   = aws_api_gateway_rest_api.ticketing_api.id
  resource_id   = aws_api_gateway_resource.venue_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "venue_get_integration" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  resource_id = aws_api_gateway_resource.venue_resource.id
  http_method = aws_api_gateway_method.venue_get_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.browse_service_arn

}

# --------------------------------------------------------------------------------

# Create /v1/performers resource, method and integration
resource "aws_api_gateway_resource" "performers_resource" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  parent_id   = aws_api_gateway_rest_api.ticketing_api.root_resource_id
  path_part   = "/v1/performers"
}

resource "aws_api_gateway_method" "performers_get_method" {
  rest_api_id   = aws_api_gateway_rest_api.ticketing_api.id
  resource_id   = aws_api_gateway_resource.performers_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "performers_get_integration" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  resource_id = aws_api_gateway_resource.performers_resource.id
  http_method = aws_api_gateway_method.performers_get_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.browse_service_arn

}

# --------------------------------------------------------------------------------

# Create /v1/events resource, method and integration
resource "aws_api_gateway_resource" "events_resource" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  parent_id   = aws_api_gateway_rest_api.ticketing_api.root_resource_id
  path_part   = "/v1/events"
}

resource "aws_api_gateway_method" "events_get_method" {
  rest_api_id   = aws_api_gateway_rest_api.ticketing_api.id
  resource_id   = aws_api_gateway_resource.events_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "events_get_integration" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  resource_id = aws_api_gateway_resource.events_resource.id
  http_method = aws_api_gateway_method.events_get_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.browse_service_arn

}

# --------------------------------------------------------------------------------

# Create /v1/event/{eventId} resource, method and integration
resource "aws_api_gateway_resource" "event_detail_resource" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  parent_id   = aws_api_gateway_rest_api.ticketing_api.root_resource_id
  path_part   = "/v1/event/{eventId}"
}

resource "aws_api_gateway_method" "event_detail_get_method" {
  rest_api_id   = aws_api_gateway_rest_api.ticketing_api.id
  resource_id   = aws_api_gateway_resource.event_detail_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "event_detail_get_integration" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  resource_id = aws_api_gateway_resource.event_detail_resource.id
  http_method = aws_api_gateway_method.event_detail_get_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.browse_service_arn

}

# --------------------------------------------------------------------------------

# Create APIGateway Permission to invoke browse_service lambda from API Gateway
resource "aws_lambda_permission" "apigw_invoke_browse_service" {
  statement_id  = "AllowAPIGatewayInvokeBrowseService"
  action        = "lambda:InvokeFunction"
  function_name = var.browse_service_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.ticketing_api.execution_arn}/*/*"
}

# --------------------------------------------------------------------------------

# Create JWT authorizer for API Gateway
resource "aws_api_gateway_authorizer" "jwt_authorizer" {
  name                   = "JWTAuthorizer"
  rest_api_id            = aws_api_gateway_rest_api.ticketing_api.id
  authorizer_result_ttl_in_seconds = 300
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [var.user_pool_arn]
  identity_source        = "method.request.header.Authorization"
}


# --------------------------------------------------------------------------------

# Create /v1/queue/enter resource, method and integration
resource "aws_api_gateway_resource" "queue_enter_resource" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  parent_id   = aws_api_gateway_rest_api.ticketing_api.root_resource_id
  path_part   = "/v1/queue/enter"
}

resource "aws_api_gateway_method" "queue_enter_post_method" {
  rest_api_id   = aws_api_gateway_rest_api.ticketing_api.id
  resource_id   = aws_api_gateway_resource.queue_enter_resource.id
  http_method   = "POST"
  authorization = "JWT" # Change to JWT authorizer once it's properly set up
}

resource "aws_api_gateway_integration" "queue_enter_post_integration" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  resource_id = aws_api_gateway_resource.queue_enter_resource.id
  http_method = aws_api_gateway_method.queue_enter_post_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.queue_service_arn

}

# --------------------------------------------------------------------------------

# Create /v1/queue/poll resource, method and integration
resource "aws_api_gateway_resource" "queue_poll_resource" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  parent_id   = aws_api_gateway_rest_api.ticketing_api.root_resource_id
  path_part   = "/v1/queue/poll"
}

resource "aws_api_gateway_method" "queue_poll_post_method" {
  rest_api_id   = aws_api_gateway_rest_api.ticketing_api.id
  resource_id   = aws_api_gateway_resource.queue_poll_resource.id
  http_method   = "POST"
  authorization = "JWT" # Change to JWT authorizer once it's properly set up
}

resource "aws_api_gateway_integration" "queue_poll_post_integration" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  resource_id = aws_api_gateway_resource.queue_poll_resource.id
  http_method = aws_api_gateway_method.queue_poll_post_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.queue_service_arn

}

# --------------------------------------------------------------------------------

# Create /v1/queue/release  resource, method and integration
resource "aws_api_gateway_resource" "queue_release_resource" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  parent_id   = aws_api_gateway_rest_api.ticketing_api.root_resource_id
  path_part   = "/v1/queue/release"
}

resource "aws_api_gateway_method" "queue_release_post_method" {
  rest_api_id   = aws_api_gateway_rest_api.ticketing_api.id
  resource_id   = aws_api_gateway_resource.queue_release_resource.id
  http_method   = "POST"
  authorization = "JWT" # Change to JWT authorizer once it's properly set up
}

resource "aws_api_gateway_integration" "queue_release_post_integration" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  resource_id = aws_api_gateway_resource.queue_release_resource.id
  http_method = aws_api_gateway_method.queue_release_post_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.queue_service_arn

}

# --------------------------------------------------------------------------------

# Create API gateway permission to invoke queue_service lambda from API Gateway
resource "aws_lambda_permission" "apigw_invoke_queue_service" {
  statement_id  = "AllowAPIGatewayInvokeQueueService"
  action        = "lambda:InvokeFunction"
  function_name = var.queue_service_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.ticketing_api.execution_arn}/*/*"
}

# --------------------------------------------------------------------------------

# Create /v1/events/{eventId}/seats resource, method and integration
resource "aws_api_gateway_resource" "event_seats_resource" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  parent_id   = aws_api_gateway_rest_api.ticketing_api.root_resource_id
  path_part   = "/v1/event/{eventId}/seats"
}

resource "aws_api_gateway_method" "event_seats_get_method" {
  rest_api_id   = aws_api_gateway_rest_api.ticketing_api.id
  resource_id   = aws_api_gateway_resource.event_seats_resource.id
  http_method   = "GET"
  authorization = "JWT" # Change to JWT authorizer once it's properly set up
}

resource "aws_api_gateway_integration" "event_seats_get_integration" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  resource_id = aws_api_gateway_resource.event_seats_resource.id
  http_method = aws_api_gateway_method.event_seats_get_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.seat_availability_service_arn

}

# --------------------------------------------------------------------------------

# Create API gateway permission to invoke seat_availability_service lambda from API Gateway
resource "aws_lambda_permission" "apigw_invoke_seat_availability_service" {
  statement_id  = "AllowAPIGatewayInvokeSeatAvailabilityService"
  action        = "lambda:InvokeFunction"
  function_name = var.seat_availability_service_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.ticketing_api.execution_arn}/*/*"
}


# --------------------------------------------------------------------------------

# Create /reserveticket resource, method and integration
resource "aws_api_gateway_resource" "reserve_ticket_resource" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  parent_id   = aws_api_gateway_rest_api.ticketing_api.root_resource_id
  path_part   = "/v1/reserveticket"
}

resource "aws_api_gateway_method" "reserve_ticket_post_method" {
  rest_api_id   = aws_api_gateway_rest_api.ticketing_api.id
  resource_id   = aws_api_gateway_resource.reserve_ticket_resource.id
  http_method   = "POST"
  authorization = "JWT" # Change to JWT authorizer once it's properly set up
}

resource "aws_api_gateway_integration" "reserve_ticket_post_integration" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  resource_id = aws_api_gateway_resource.reserve_ticket_resource.id
  http_method = aws_api_gateway_method.reserve_ticket_post_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.reservation_service_arn

}

# --------------------------------------------------------------------------------

# Create API gateway permission to invoke reservation_service lambda from API Gateway
resource "aws_lambda_permission" "apigw_invoke_reservation_service" {
  statement_id  = "AllowAPIGatewayInvokeReservationService"
  action        = "lambda:InvokeFunction"
  function_name = var.reservation_service_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.ticketing_api.execution_arn}/*/*"
}

# --------------------------------------------------------------------------------

# Create /v1/payment resource, method and integration
resource "aws_api_gateway_resource" "payment_resource" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  parent_id   = aws_api_gateway_rest_api.ticketing_api.root_resource_id
  path_part   = "/v1/payment"
}

resource "aws_api_gateway_method" "payment_post_method" {
  rest_api_id   = aws_api_gateway_rest_api.ticketing_api.id
  resource_id   = aws_api_gateway_resource.payment_resource.id
  http_method   = "POST"
  authorization = "JWT" # Change to JWT authorizer once it's properly set up
}

resource "aws_api_gateway_integration" "payment_post_integration" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  resource_id = aws_api_gateway_resource.payment_resource.id
  http_method = aws_api_gateway_method.payment_post_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.payment_service_arn

}   

# --------------------------------------------------------------------------------

# Create API gateway permission to invoke payment_service lambda from API Gateway
resource "aws_lambda_permission" "apigw_invoke_payment_service" {
  statement_id  = "AllowAPIGatewayInvokePaymentService"
  action        = "lambda:InvokeFunction"
  function_name = var.payment_service_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.ticketing_api.execution_arn}/*/*"
}


# --------------------------------------------------------------------------------

# Create /v1/booking resource, method and integration
resource "aws_api_gateway_resource" "booking_resource" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  parent_id   = aws_api_gateway_rest_api.ticketing_api.root_resource_id
  path_part   = "/v1/booking"
}

resource "aws_api_gateway_method" "booking_post_method" {
  rest_api_id   = aws_api_gateway_rest_api.ticketing_api.id
  resource_id   = aws_api_gateway_resource.booking_resource.id
  http_method   = "POST"
  authorization = "JWT" # Change to JWT authorizer once it's properly set up
}

resource "aws_api_gateway_integration" "booking_post_integration" {
  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
  resource_id = aws_api_gateway_resource.booking_resource.id
  http_method = aws_api_gateway_method.booking_post_method.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.confirmation_service_arn

}

# --------------------------------------------------------------------------------

# Create API gateway permission to invoke confirmation_service lambda from API Gateway
resource "aws_lambda_permission" "apigw_invoke_confirmation_service" {
  statement_id  = "AllowAPIGatewayInvokeConfirmationService"
  action        = "lambda:InvokeFunction"
  function_name = var.confirmation_service_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.ticketing_api.execution_arn}/*/*"
}


# --------------------------------------------------------------------------------

# Create APIGateway deployment
resource "aws_api_gateway_deployment" "ticketing_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.location_get_integration,
    aws_api_gateway_integration.venue_get_integration,
    aws_api_gateway_integration.performers_get_integration,
    aws_api_gateway_integration.events_get_integration,
    aws_api_gateway_integration.event_detail_get_integration,
    aws_api_gateway_integration.queue_enter_post_integration,
    aws_api_gateway_integration.queue_poll_post_integration,
    aws_api_gateway_integration.queue_release_post_integration,
    aws_api_gateway_integration.event_seats_get_integration,
    aws_api_gateway_integration.reserve_ticket_post_integration,
    aws_api_gateway_integration.payment_post_integration,
    aws_api_gateway_integration.booking_post_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.ticketing_api.id
 
}

# Create API Gateway stage
resource "aws_api_gateway_stage" "ticketing_api_stage" {
  stage_name    = "prod"
  rest_api_id   = aws_api_gateway_rest_api.ticketing_api.id
  deployment_id = aws_api_gateway_deployment.ticketing_api_deployment.id
}
