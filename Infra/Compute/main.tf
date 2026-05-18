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
resource "aws_iam_role" "lambda_role_ticket_system" {
  name = "lambda-role_ticket-system"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Create a lambda role policy attachement with accesing RDS proxy policy
resource "aws_iam_role_policy_attachment" "lambda_attach_rds_proxy" {
  role       = aws_iam_role.lambda_role_ticket_system.name
  policy_arn = aws_iam_policy.lambda_rds_proxy_policy.arn

}

# Create a lambda role policy attachement with accesing Elasticache
resource "aws_iam_role_policy_attachment" "lambda_attach_elasticache" {
  role       = aws_iam_role.lambda_role_ticket_system.name
  policy_arn = aws_iam_policy.lambda_elasticache_policy.arn
}



# Create a lambda role policy attachement with Basic Execution Policy for accessing Cloudwatch
resource "aws_iam_role_policy_attachment" "lambda_basic_execution_policy" {
  role       = aws_iam_role.lambda_role_ticket_system.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}



# Create an Ingress rule for Lambda Security Group
#resource "aws_vpc_security_group_ingress_rule" "rds_proxy_sg_ingress_rule" {
#  security_group_id = security_group_id
#  referenced_security_group_id = var.referenced_security_group_id
#  from_port         = 5432
#  ip_protocol       = "tcp"
#  to_port           = 5432
#}

# Creating an Egress rule from Lambda security group to RDS Proxy
resource "aws_vpc_security_group_egress_rule" "lambda_sg_egress_rds_proxy_rule" {
  security_group_id = var.security_group_id
  referenced_security_group_id  = var.db_proxy_security_group
  from_port   = 5432
  ip_protocol = "tcp"
  to_port     = 5432
}

# Create and Egress rule for Lambda Security Group to Elasticache
resource "aws_vpc_security_group_egress_rule" "elasticache_sg_egress_rule" {
  security_group_id = var.security_group_id
  referenced_security_group_id  = var.elasticache_security_group
  from_port   = 6379
  ip_protocol = "tcp"
  to_port     = 6379
}


# Create a Lambda with IAM Role and Security Group (Table Creation)

# Create a Lambda with IAM Role and Security Group (Browse Service)


# Create a Lambda with IAM Role and Security Group (Queue Service)



# Create a Lambda with IAM Role and Security Group (Seat Availbility Service)


# Create a Lambda with IAM Role and Security Group (Reservation  Service)


# Create a Lambda with IAM Role and Security Group (Booking Service)