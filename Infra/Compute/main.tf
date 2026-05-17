# Create a lambda policy for assume lambda role

resource "aws_iam_policy" "lambda_assume_role_policy" {
  name        = "lambda-assume-role-policy"
  description = "Allow Lambda to access DynamoDB short URL table"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
       {
    effect = "Allow"

    principals =  {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
    ]
  })
}



# Create a lambda policy for accessing RDS Proxy
resource "aws_iam_policy" "lambda_rds_proxy_policy" {
  name        = "lambda-rds-proxy"
  description = "Allow Lambda to access RDS Proxy"

  policy = jsonencode({
    Version = "2012-10-17"
    "Statement": [
    {
      "Sid": "AllowRDSProxyConnection",
      "Effect": "Allow",
      "Action": [
        "rds-db:connect"
      ],
      "Resource": [
        "arn:aws:rds-db:${var.region}:${var.account_id}:dbuser:${var.db_proxy_id}/*"
      ]
    },
    {
      "Sid": "AllowDescribeRDSProxy",
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBProxies",
        "rds:DescribeDBProxyTargets",
        "rds:DescribeDBProxyTargetGroups"
      ],
      "Resource": "arn:aws:rds:${var.region}:${var.account_id}:db-proxy:${var.db_proxy_id}/*"
    }
  ]
  })
}


# Create a Lambda Role 
resource "aws_iam_role" "lambda_role" {
  name               = "lambda_role"
  assume_role_policy = aws_iam_policy.lambda_assume_role_policy.arn
}

# Create a lambda role policy attachement with accesing RDS proxy policy
resource "aws_iam_role_policy_attachment" "lambda_attach_dynamodb" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_rds_proxy_policy.arn
}


# Create a lambda role policy attachement with Basic Execution Policy for accessing Cloudwatch
resource "aws_iam_role_policy_attachment" "lambda_basic_execution_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Create a Security Group for Lambda 
resource "aws_security_group" "lambda_sg" {
  name        = "lambda-sg"
  description = "Allow TLS inbound traffic from lambda"
  vpc_id      = var.vpc_id

  tags = {
    Application = "Elasticache"
    Type = "Security_Group"
  }
}

# Create an Ingress rule for Lambda Security Group

# Create an Egress rule for Lmabda Security Group to Elasticache


# Create and Egress rule for Lambda Security Group to RDS Proxy


# Create a Lambda with IAM Role and Security Group (Browse Service)


# Create a Lambda with IAM Role and Security Group (Queue Service)



# Create a Lambda with IAM Role and Security Group (Seat Availbility Service)


# Create a Lambda with IAM Role and Security Group (Reservation  Service)


# Create a Lambda with IAM Role and Security Group (Booking Service)