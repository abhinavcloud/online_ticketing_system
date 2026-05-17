output "lambda_sg" {
    value = aws_security_group.lambda_sg.id
    description = "Lambda Security Group id"
}