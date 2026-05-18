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
      "Resource": "*"
    }
  ]
  })
}

# Create an iam policy to access the elasticache serveless clusters
resource "aws_iam_policy" "lambda_elasticache_policy" {
  name        = "lambda-elasticache-proxy"
  description = "Allow Lambda to access elasticache clusters"

  policy = jsonencode({
    Version = "2012-10-17"
    "Statement": [
    {
      "Sid": "ElastiCacheServerlessIamAuthConnect",
      "Effect": "Allow",
      "Action": "elasticache:Connect",
    
      "Resource": [var.browse_cache, var.active_user_lock_cache, var.seat_lock_cache, var.user]
    },

    {
      "Sid": "ElastiCacheReadOnlyDiscovery",
      "Effect": "Allow",
      "Action": [
        "elasticache:DescribeServerlessCaches",
        "elasticache:DescribeUsers",
        "elasticache:DescribeUserGroups"
      ],
      "Resource": "*"
    
        }
      ]
  }
  )
}


# Create a Lambda Role 
resource "aws_iam_role" "lambda_role" {
  name               = "lambda_role"
  assume_role_policy = jsonencode({
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

# Create a lambda role policy attachement with accesing RDS proxy policy
resource "aws_iam_role_policy_attachment" "lambda_attach_rds_proxy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_rds_proxy_policy.arn

}

# Create a lambda role policy attachement with accesing Elasticache
resource "aws_iam_role_policy_attachment" "lambda_attach_elasticache" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_elasticache_policy.arn
}



# Create a lambda role policy attachement with Basic Execution Policy for accessing Cloudwatch
resource "aws_iam_role_policy_attachment" "lambda_basic_execution_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}



# Create an Ingress rule for Lambda Security Group

# Create an Egress rule for Lmabda Security Group to Elasticache


# Create and Egress rule for Lambda Security Group to RDS Proxy


# Create a Lambda with IAM Role and Security Group (Table Creation)

# Create a Lambda with IAM Role and Security Group (Browse Service)


# Create a Lambda with IAM Role and Security Group (Queue Service)



# Create a Lambda with IAM Role and Security Group (Seat Availbility Service)


# Create a Lambda with IAM Role and Security Group (Reservation  Service)


# Create a Lambda with IAM Role and Security Group (Booking Service)