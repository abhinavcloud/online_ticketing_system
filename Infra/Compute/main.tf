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
        "arn:aws:rds-db:${var.region}:${var.account_id}:dbuser:${var.db_proxy_id}/${var.db_user}"
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
    },
    
    {
        Sid    = "AllowGetDbToken",
        Effect = "Allow",
        Action = ["rds:GenerateDbAuthToken"],
        Resource = ["*"]
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



# Create a lambda role policy attachment to access resources inside VPC
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_role_ticket_system.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}


# Create a lambda policy to publish notifications to SNS topic
resource "aws_iam_policy" "lambda_sns_publish_policy" {
  name        = "lambda-sns-publish"
  description = "Allow Lambda to publish to SNS topic for notifications"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid: "AllowSnsPublish",
      Effect: "Allow",
      Action: "sns:Publish",
      Resource: var.notification_topic_arn
    }]
  })
}


# Create a lambda role policy attachment to allow publish to SNS topic for notifications
resource "aws_iam_role_policy_attachment" "lambda_notification_access" {
  role = aws_iam_role.lambda_role_ticket_system.name
  policy_arn = aws_iam_policy.lambda_sns_publish_policy.arn
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

# Create an Egress rule for Lambda Security Group to VPC Endpoint
resource "aws_vpc_security_group_egress_rule" "lambda_to_kms_vpce_443" {
  security_group_id            = var.security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = var.vpc_endpoint_security_group
  description                  = "Allow Lambda to call KMS via VPCE on 443"
}



# Create a Lambda with IAM Role and Security Group (Browse Service)
data "archive_file" "browse_layer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../Code/browse_service_layer"
  output_path = "${path.module}/artifacts/browse_service_layer.zip"
}

resource "aws_lambda_layer_version" "browse_deps" {
  layer_name          = "browse-service-deps"
  filename            = data.archive_file.browse_layer_zip.output_path
  source_code_hash    = data.archive_file.browse_layer_zip.output_base64sha256
  compatible_runtimes = ["python3.12"]
}

data "archive_file" "browse_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../Code/browse_service"
  output_path = "${path.module}/artifacts/browse_service.zip"
}

resource "aws_lambda_function" "browse_service" {
  function_name = "browse-service"
  description   = "Browse Service: locations/venues/performers/events/event-details"
  runtime       = "python3.12"
  handler       = "app.handler"
  timeout       = 30
  memory_size   = 512

  filename         = data.archive_file.browse_lambda_zip.output_path
  source_code_hash = data.archive_file.browse_lambda_zip.output_base64sha256

  role = aws_iam_role.lambda_role_ticket_system.arn

  layers = [
    aws_lambda_layer_version.browse_deps.arn
  ]

  vpc_config {
    subnet_ids         = var.subnet_group
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = {
      APP_REGION = var.region

      # DB (RDS Proxy IAM)
      DB_HOST = var.db_proxy_endpoint
      DB_PORT = tostring(var.db_port)
      DB_NAME = var.db_name
      DB_USER = var.db_user

      # Browse cache (Valkey serverless IAM)
      BROWSE_CACHE_ENDPOINT     = var.browse_cache_endpoint
      BROWSE_CACHE_PORT         = tostring(var.browse_cache_port)
      BROWSE_CACHE_NAME         = var.browse_cache_name
      ELASTICACHE_USER_ID       = var.elasticache_user_id
      BROWSE_CACHE_TTL_SECONDS  = tostring(var.browse_cache_ttl_seconds)
    }
  }

  tags = {
    Service = "ticketing"
    Name    = "browse-service"
  }
}

# Create a Lambda with IAM Role and Security Group (Queue Service)
## Create a KMS key for JWT signing
resource "aws_kms_key" "queue_jwt_signing_key" {
  description              = "KMS asymmetric key for Queue Service JWT signing"
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "RSA_2048"
  deletion_window_in_days  = 7

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Full admin to account root
      {
        Sid: "AllowRootAdmin",
        Effect: "Allow",
        Principal: { AWS: "arn:aws:iam::${var.account_id}:root" },
        Action: "kms:*",
        Resource: "*"
      },
      # Allow Lambda role to sign + fetch public key
      {
        Sid: "AllowLambdaUseKey",
        Effect: "Allow",
        Principal: { AWS: aws_iam_role.lambda_role_ticket_system.arn },
        Action: [
          "kms:Sign",
          "kms:GetPublicKey",
          "kms:DescribeKey"
        ],
        Resource: "*"
      }
    ]
  })
}

resource "aws_kms_alias" "queue_jwt_signing_key_alias" {
  name          = "alias/queue-jwt-signing"
  target_key_id = aws_kms_key.queue_jwt_signing_key.key_id
}

##IAM permissions for Queue Lambda
resource "aws_iam_policy" "lambda_kms_sign_policy" {
  name        = "lambda-queue-kms-sign"
  description = "Allow Queue service lambda to sign JWT with KMS"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid: "AllowKmsSign",
      Effect: "Allow",
      Action: [
        "kms:Sign",
        "kms:GetPublicKey",
        "kms:DescribeKey"
      ],
      Resource: aws_kms_key.queue_jwt_signing_key.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_attach_kms_sign" {
  role       = aws_iam_role.lambda_role_ticket_system.name
  policy_arn = aws_iam_policy.lambda_kms_sign_policy.arn
}


data "archive_file" "queue_layer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../Code/queue_service_layer"
  output_path = "${path.module}/artifacts/queue_service_layer.zip"
}


resource "aws_lambda_layer_version" "queue_deps" {
  layer_name          = "queue-service-deps"
  filename            = data.archive_file.queue_layer_zip.output_path
  source_code_hash    = data.archive_file.queue_layer_zip.output_base64sha256
  compatible_runtimes = ["python3.12"]
}


data "archive_file" "queue_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../Code/queue_service"
  output_path = "${path.module}/artifacts/queue_service.zip"
}


resource "aws_lambda_function" "queue_service" {
  function_name = "queue-service"
  description   = "Queue Service: POST /queue/enter"
  runtime       = "python3.12"
  handler       = "app.handler"
  timeout       = 60
  memory_size   = 512

  filename         = data.archive_file.queue_lambda_zip.output_path
  source_code_hash = data.archive_file.queue_lambda_zip.output_base64sha256

  role = aws_iam_role.lambda_role_ticket_system.arn

  layers = [
    aws_lambda_layer_version.queue_deps.arn
  ]

  vpc_config {
    subnet_ids         = var.subnet_group
    security_group_ids = [var.security_group_id]
  }

environment {
  variables = {
    # -------------------------------------------------------------------
    # Cache A: Queue Cache == Active User Lock Cache (Valkey Serverless IAM)
    # -------------------------------------------------------------------
    ACTIVE_USERS_CACHE_ENDPOINT = var.active_users_cache_endpoint
    ACTIVE_USERS_CACHE_PORT     = tostring(var.active_users_cache_port)
    ACTIVE_USERS_CACHE_NAME     = var.active_users_cache_name
    ELASTICACHE_USER_ID         = var.elasticache_user_id

    # -------------------------------------------------------------------
    # Cache B: Seat Lock Cache (Valkey Serverless IAM)  [not used yet]
    # -------------------------------------------------------------------
    SEAT_LOCK_CACHE_ENDPOINT    = var.seat_lock_cache_endpoint
    SEAT_LOCK_CACHE_PORT        = tostring(var.seat_lock_cache_port)
    SEAT_LOCK_CACHE_NAME        = var.seat_lock_cache_name
    SEAT_LOCK_ELASTICACHE_USER_ID = var.elasticache_user_id

    # -------------------------------------------------------------------
    # Queue behavior (HLD-driven + safe guardrails)
    # -------------------------------------------------------------------
    QUEUE_ALLOWED_TTL_SECONDS          = "600"  # 10 minutes
    QUEUE_POLL_AFTER_SECONDS           = "5"
    QUEUE_OVERSELL_FACTOR              = "2"

    # Active concurrency limit per event-category
    QUEUE_MAX_USERS_PER_EVENT_CATEGORY = "1"

    # Promotion coordination/guardrails (NOT business logic)
    QUEUE_PROMOTION_LOCK_SECONDS = "1"     # short mutex to avoid double promotions
    QUEUE_MAX_PROMOTE_PER_POLL   = "25"    # safety cap; computed releasableUsers still drives promotion size

    # DB (RDS Proxy IAM)
    DB_HOST = var.db_proxy_endpoint
    DB_PORT = tostring(var.db_port)
    DB_NAME = var.db_name
    DB_USER = var.db_user
    APP_REGION = var.region
    DB_SSLMODE     = "require"
    DB_IAM_TOKEN_REFRESH_SECONDS = "840"
    # -------------------------------------------------------------------
    # JWT signing via KMS
    # -------------------------------------------------------------------
    JWT_KMS_KEY_ID = aws_kms_key.queue_jwt_signing_key.key_id
    JWT_ALG        = "RS256"
    JWT_ISSUER     = "ticketing-queue"
  }
}
}



# Create a Lambda with IAM Role and Security Group (Seat Availbility Service)
data "archive_file" "seat_availability_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../Code/seat_availibility_service"
  output_path = "${path.module}/artifacts/seat_availibility_service.zip"
}


data "archive_file" "seat_availability_layer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../Code/seat_availibility_service_layer"
  output_path = "${path.module}/artifacts/seat_availibility_service_layer.zip"
}

resource "aws_lambda_layer_version" "seat_availability_deps" {
  layer_name          = "seat-availability-service-deps"
  filename            = data.archive_file.seat_availability_layer_zip.output_path
  source_code_hash    = data.archive_file.seat_availability_layer_zip.output_base64sha256
  compatible_runtimes = ["python3.12"]
}

resource "aws_lambda_function" "seat_availability_service" {
  function_name = "seat-availability-service"
  description   = "Seat Availability Service: GET /v1/events/{eventId}/seats?category_id=... (read-only)"
  runtime       = "python3.12"
  handler       = "app.handler"
  timeout       = 30
  memory_size   = 512

  filename         = data.archive_file.seat_availability_lambda_zip.output_path
  source_code_hash = data.archive_file.seat_availability_lambda_zip.output_base64sha256

  role = aws_iam_role.lambda_role_ticket_system.arn

  layers = [
    aws_lambda_layer_version.seat_availability_deps.arn
  ]

  vpc_config {
    subnet_ids         = var.subnet_group
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = {
      # Use APP_REGION (do NOT set AWS_REGION - it's reserved by Lambda)
      APP_REGION = var.region

      # -----------------------------
      # DB (RDS Proxy IAM)
      # -----------------------------
      DB_HOST = var.db_proxy_endpoint
      DB_PORT = tostring(var.db_port)
      DB_NAME = var.db_name
      DB_USER = var.db_user

      DB_SSLMODE                 = "require"
      DB_IAM_TOKEN_REFRESH_SECONDS = "840"

      # -----------------------------
      # Cache A (Queue cache == Active Users cache)
      # Used to verify sessionId is ALLOWED
      # -----------------------------
      ACTIVE_USERS_CACHE_ENDPOINT = var.active_users_cache_endpoint
      ACTIVE_USERS_CACHE_PORT     = tostring(var.active_users_cache_port)
      ACTIVE_USERS_CACHE_NAME     = var.active_users_cache_name
      ELASTICACHE_USER_ID         = var.elasticache_user_id

      # -----------------------------
      # Cache B (Seat Lock cache) - READ ONLY here
      # Reservation service will write locks to this cache
      # -----------------------------
      SEAT_LOCK_CACHE_ENDPOINT          = var.seat_lock_cache_endpoint
      SEAT_LOCK_CACHE_PORT              = tostring(var.seat_lock_cache_port)
      SEAT_LOCK_CACHE_NAME              = var.seat_lock_cache_name
      SEAT_LOCK_ELASTICACHE_USER_ID     = var.elasticache_user_id

      # -----------------------------
      # Behavior knobs
      # -----------------------------
      SEATS_PAGE_SIZE          = "200"
      SHOW_LOCK_EXPIRES_AT     = "false"
      JWT_KMS_KEY_ID = aws_kms_key.queue_jwt_signing_key.key_id
      JWT_ALG        = "RS256"
      JWT_ISSUER     = "ticketing-queue"
    
    }
  }

  tags = {
    Service = "ticketing"
    Name    = "seat-availability-service"
  }
}


# Create a Lambda with IAM Role and Security Group (Reservation  Service)
data "archive_file" "reservation_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../Code/reservation_service"
  output_path = "${path.module}/artifacts/reservation_service.zip"
}


data "archive_file" "reservation_layer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../Code/reservation_service_layer"
  output_path = "${path.module}/artifacts/reservation_service_layer.zip"
}

resource "aws_lambda_layer_version" "reservation_deps" {
  layer_name          = "reservation-service-deps"
  filename            = data.archive_file.reservation_layer_zip.output_path
  source_code_hash    = data.archive_file.reservation_layer_zip.output_base64sha256
  compatible_runtimes = ["python3.12"]
}

resource "aws_lambda_function" "reservation_service" {
  function_name = "reservation-service"
  description   = "Reservation Service: POST /v1/events/{eventId}/reservations"
  runtime       = "python3.12"
  handler       = "app.handler"
  timeout       = 30
  memory_size   = 512

  filename         = data.archive_file.reservation_lambda_zip.output_path
  source_code_hash = data.archive_file.reservation_lambda_zip.output_base64sha256

  role = aws_iam_role.lambda_role_ticket_system.arn

  layers = [
    aws_lambda_layer_version.reservation_deps.arn
  ]

  vpc_config {
    subnet_ids         = var.subnet_group
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = {
      # Use APP_REGION (do NOT set AWS_REGION - it's reserved by Lambda)
      APP_REGION = var.region

      # -----------------------------
      # DB (RDS Proxy IAM)
      # -----------------------------
      DB_HOST = var.db_proxy_endpoint
      DB_PORT = tostring(var.db_port)
      DB_NAME = var.db_name
      DB_USER = var.db_user

      DB_SSLMODE                 = "require"
      DB_IAM_TOKEN_REFRESH_SECONDS = "840"

      # -----------------------------
      # Cache A (Queue cache == Active Users cache)
      # Used to verify sessionId is ALLOWED
      # -----------------------------
      ACTIVE_USERS_CACHE_ENDPOINT = var.active_users_cache_endpoint
      ACTIVE_USERS_CACHE_PORT     = tostring(var.active_users_cache_port)
      ACTIVE_USERS_CACHE_NAME     = var.active_users_cache_name
      ELASTICACHE_USER_ID         = var.elasticache_user_id

      # -----------------------------
      # Cache B (Seat Lock cache) - READ ONLY here
      # Reservation service will write locks to this cache
      # -----------------------------
      SEAT_LOCK_CACHE_ENDPOINT          = var.seat_lock_cache_endpoint
      SEAT_LOCK_CACHE_PORT              = tostring(var.seat_lock_cache_port)
      SEAT_LOCK_CACHE_NAME              = var.seat_lock_cache_name
      SEAT_LOCK_ELASTICACHE_USER_ID     = var.elasticache_user_id

      # -----------------------------
      # Behavior knobs
      # -----------------------------
      SEATS_PAGE_SIZE          = "200"
      SHOW_LOCK_EXPIRES_AT     = "false"
      #-----------------------------
      # Authentication/Authorization (JWT via KMS)
      #-----------------------------
      JWT_KMS_KEY_ID = aws_kms_key.queue_jwt_signing_key.key_id
      JWT_ALG        = "RS256"
      JWT_ISSUER     = "ticketing-queue"
    }
  }

  tags = {
    Service = "ticketing"
    Name    = "reservation-service"
  }
}


# Create a Lambda with IAM Role and Security Group (Mock Payment Service)
data "archive_file" "payment_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../Code/payment_service"
  output_path = "${path.module}/artifacts/payment_service.zip"
}



resource "aws_lambda_function" "payment_service" {
  function_name = "payment-service"
  description   = "payment Service: https://payment-gateway.com/pay?amount=9000&currency=INR&reference=res_123&returnUrl=https://your-frontend.com/payment/return?reservationId=res_123"
  runtime       = "python3.12"
  handler       = "app.handler"
  timeout       = 30
  memory_size   = 512

  filename         = data.archive_file.payment_lambda_zip.output_path
  source_code_hash = data.archive_file.payment_lambda_zip.output_base64sha256

  role = aws_iam_role.lambda_role_ticket_system.arn # Reusing the same role, but we can also strip down and create specific role for this mock service 

  # Layers is not needed for mock
  #layers = [
  #  aws_lambda_layer_version.reservation_deps.arn
  #]

  vpc_config {
    subnet_ids         = var.subnet_group
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = {
      PAYMENT_MOCK_MODE = "always_success" # Other values include "random", "always_failure"
      PAYMENT_MOCK_FAILURE_RATE = "0.1" # Percentage of falires if payment mock mode is random
    }
  }

  tags = {
    Service = "ticketing"
    Name    = "reservation-service"
  }
}

# Create a Lambda with IAM Role and Security Group (Confirmation  Service)
data "archive_file" "confirmation_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../Code/confirmation_service"
  output_path = "${path.module}/artifacts/confirmation_service.zip"
}


data "archive_file" "confirmation_layer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../Code/confirmation_service_layer"
  output_path = "${path.module}/artifacts/confirmation_service_layer.zip"
}

resource "aws_lambda_layer_version" "confirmation_deps" {
  layer_name          = "confirmation-service-deps"
  filename            = data.archive_file.confirmation_layer_zip.output_path
  source_code_hash    = data.archive_file.confirmation_layer_zip.output_base64sha256
  compatible_runtimes = ["python3.12"]
}

resource "aws_lambda_function" "confirmation_service" {
  function_name = "confirmation-service"
  description   = "Confirmation Service: POST /v1/events/{eventId}/reservations"
  runtime       = "python3.12"
  handler       = "app.handler"
  timeout       = 30
  memory_size   = 512

  filename         = data.archive_file.confirmation_lambda_zip.output_path
  source_code_hash = data.archive_file.confirmation_lambda_zip.output_base64sha256

  role = aws_iam_role.lambda_role_ticket_system.arn

  layers = [
    aws_lambda_layer_version.confirmation_deps.arn
  ]

  vpc_config {
    subnet_ids         = var.subnet_group
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = {
      # Use APP_REGION (do NOT set AWS_REGION - it's reserved by Lambda)
      APP_REGION = var.region

      # -----------------------------
      # DB (RDS Proxy IAM)
      # -----------------------------
      DB_HOST = var.db_proxy_endpoint
      DB_PORT = tostring(var.db_port)
      DB_NAME = var.db_name
      DB_USER = var.db_user
      DB_SSLMODE                 = "require"
      DB_IAM_TOKEN_REFRESH_SECONDS = "840"
      JWT_KMS_KEY_ID = aws_kms_key.queue_jwt_signing_key.key_id
      JWT_ALG        = "RS256"
      JWT_ISSUER     = "ticketing-queue"
      NOTIFICATION_TOPIC_ARN = var.notification_topic_arn
      # -----------------------------
      # Cache A (Queue cache == Active Users cache)
      # Used to verify sessionId is ALLOWED
      # -----------------------------
      ACTIVE_USERS_CACHE_ENDPOINT = var.active_users_cache_endpoint
      ACTIVE_USERS_CACHE_PORT     = tostring(var.active_users_cache_port)
      ACTIVE_USERS_CACHE_NAME     = var.active_users_cache_name
      ELASTICACHE_USER_ID         = var.elasticache_user_id

      # -----------------------------
      # Cache B (Seat Lock cache) - READ ONLY here
      # Reservation service will write locks to this cache
      # -----------------------------
      SEAT_LOCK_CACHE_ENDPOINT          = var.seat_lock_cache_endpoint
      SEAT_LOCK_CACHE_PORT              = tostring(var.seat_lock_cache_port)
      SEAT_LOCK_CACHE_NAME              = var.seat_lock_cache_name
      SEAT_LOCK_ELASTICACHE_USER_ID     = var.elasticache_user_id

  }

      
    }
  
  tags = {
    Service = "ticketing"
    Name    = "confirmation-service"
  }
}
