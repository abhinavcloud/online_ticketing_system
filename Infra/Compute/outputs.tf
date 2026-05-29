# Generate Lambda ARNs and name as outputs to use in APIGateway Module

    output "browse_service_arn" {
        value = aws_lambda_function.browse_service.arn
        description = "ARN of the Browse Service Lambda function"
    }

output "browse_service_name" {
    value = aws_lambda_function.browse_service.function_name
    description = "Name of the Browse Service Lambda function"
}


output "queue_service_arn" {
    value = aws_lambda_function.queue_service.arn
    description = "ARN of the Queue Service Lambda function"

}

output "queue_service_name" {
    value = aws_lambda_function.queue_service.function_name
    description = "Name of the Queue Service Lambda function"

}

output "seat_availability_service_arn" {
    value = aws_lambda_function.seat_availability_service.arn
    description = "ARN of the Seat Availability Service Lambda function"

}


output "seat_availability_service_name" {
    value = aws_lambda_function.seat_availability_service.function_name
    description = "Name of the Seat Availability Service Lambda function"

}


output "reservation_service_arn" {
    value = aws_lambda_function.reservation_service.arn
    description = "ARN of the Reservation Service Lambda function"

}

output "reservation_service_name" {
    value = aws_lambda_function.reservation_service.function_name
    description = "Name of the Reservation Service Lambda function"

}

output "payment_service_arn" {
    value = aws_lambda_function.payment_service.arn
    description = "ARN of the Payment Service Lambda function"

}

output "payment_service_name" {
    value = aws_lambda_function.payment_service.function_name
    description = "Name of the Payment Service Lambda function"

}

output "confirmation_service_arn" {
    value = aws_lambda_function.confirmation_service.arn
    description = "ARN of the Confirmation Service Lambda function"

}

output "confirmation_service_name" {
    value = aws_lambda_function.confirmation_service.function_name
    description = "Name of the Confirmation Service Lambda function"

}
