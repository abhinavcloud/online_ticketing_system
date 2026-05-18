# Creating DB Subnet Group
resource "aws_db_subnet_group" "aurora_db_subnet_group" {
  name       = "main"
  subnet_ids = var.subnet_group

}

#Creating a DB Security Group to Allow Incoming Request to Aurora DB
resource "aws_security_group" "aurora_sg" {
  name        = "aurora_sg"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = var.vpc_id

  tags = {
    Application = "Aurora"
    Type = "Security_Group"
  }
}

#Creating an Ingress rule to port 5432 to Aurora Cluster from rds proxy security group
resource "aws_vpc_security_group_ingress_rule" "aurora_sg_ingress_rule" {
  security_group_id = aws_security_group.aurora_sg.id
  referenced_security_group_id = aws_security_group.rds_proxy_sg.id
  from_port         = 5432
  ip_protocol       = "tcp"
  to_port           = 5432
}

# Egress rule is not needed


#Creating an Aurora Serverless DB Cluster
resource "aws_rds_cluster" "online-ticketing-system" {
  cluster_identifier = "onlineticketingsystem"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = "17.7"
  database_name      = "onlineticketingsystem"
  master_username    = var.master_username
  master_password    = var.master_password
  storage_encrypted  = true
  db_subnet_group_name = aws_db_subnet_group.aurora_db_subnet_group.name
  enable_http_endpoint = false
  vpc_security_group_ids = [aws_security_group.aurora_sg.id]
  iam_database_authentication_enabled = true
  skip_final_snapshot = true
  serverlessv2_scaling_configuration {
    max_capacity             = 1.0
    min_capacity             = 0.0
    seconds_until_auto_pause = 600
  }
}

# Creating the writer instance in AZ 1
resource "aws_rds_cluster_instance" "writer_instance" {
  cluster_identifier = aws_rds_cluster.online-ticketing-system.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.online-ticketing-system.engine
  engine_version     = aws_rds_cluster.online-ticketing-system.engine_version
  availability_zone = var.availability_zones[0]
  db_subnet_group_name = aws_db_subnet_group.aurora_db_subnet_group.name
  publicly_accessible = false
  promotion_tier = 0
}

# Creating the reader instance in AZ 2
resource "aws_rds_cluster_instance" "reader_instance_01" {
  cluster_identifier = aws_rds_cluster.online-ticketing-system.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.online-ticketing-system.engine
  engine_version     = aws_rds_cluster.online-ticketing-system.engine_version
  availability_zone = var.availability_zones[1]
  db_subnet_group_name = aws_db_subnet_group.aurora_db_subnet_group.name
  publicly_accessible = false
  promotion_tier = 1
  depends_on = [aws_rds_cluster_instance.writer_instance]
}

# Creating the reader instance in AZ 3
resource "aws_rds_cluster_instance" "reader_instance_02" {
  cluster_identifier = aws_rds_cluster.online-ticketing-system.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.online-ticketing-system.engine
  engine_version     = aws_rds_cluster.online-ticketing-system.engine_version
  availability_zone = var.availability_zones[2]
  db_subnet_group_name = aws_db_subnet_group.aurora_db_subnet_group.name
  publicly_accessible = false
  promotion_tier = 1
  depends_on = [aws_rds_cluster_instance.writer_instance]
}

# Create a policy to attach to a IAM role for RDS Proxy to connect to Aurora DB via IAM Authentication
resource "aws_iam_policy" "rds_proxy_allow_aurora_db_connection" {
  name        = "rds-proxy-allow-aurora-db-connection"
  path        = "/"
  description = "This is an Allow Policy for RDS Proxy to allow to connect to Aurora DB Cluster since we will be using end to end IAM authentication for DB connections"

  policy = jsonencode({
    "Version":"2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "rds-db:connect"
            ],
            "Resource": [
                "arn:aws:rds-db:${var.region}:${var.account_id}:dbuser:${aws_rds_cluster.online-ticketing-system.cluster_resource_id}/*"
            ]
        }
    ]
})
}

# Create an IAM Assume role policy for RDS Proxy to to assume the role as principal
data "aws_iam_policy_document" "rds_proxy_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}



# Create a RDS Proxy role with the Assume Role Policy identifying the principal who can assume this role.
resource "aws_iam_role" "rds_proxy_role" {
  name               = "rds-proxy-role"
  assume_role_policy = data.aws_iam_policy_document.rds_proxy_assume_role.json
}

# Attach the aurora db connect policy to the rds proxy role
resource "aws_iam_role_policy_attachment" "attach_rds_proxy_allow_aurora_db_connection" {
  role       = aws_iam_role.rds_proxy_role.name
  policy_arn = aws_iam_policy.rds_proxy_allow_aurora_db_connection.arn
}



# Create a security group for RDS Proxy to Allow Egress to Aurora DB Cluster and Ingress from Lambda
resource "aws_security_group" "rds_proxy_sg" {
  name        = "rds-proxy-sg"
  description = "Allow TLS inbound traffic from lambda and outbound traffic to aurora cluster"
  vpc_id      = var.vpc_id

  tags = {
    Application = "RDS_Proxy"
    Type = "Security_Group"
  }
}

# Creating an Ingress rule from lambda security group to rds proxy security group
resource "aws_vpc_security_group_ingress_rule" "rds_proxy_sg_ingress_rule" {
  security_group_id = aws_security_group.rds_proxy_sg.id
  referenced_security_group_id = var.referenced_security_group_id
  from_port         = 5432
  ip_protocol       = "tcp"
  to_port           = 5432
}

# Creating an Egress rule from RDS Proxy security group to Aurora security group
resource "aws_vpc_security_group_egress_rule" "rds_proxy_sg_egress_rule" {
  security_group_id = aws_security_group.rds_proxy_sg.id
  referenced_security_group_id  = aws_security_group.aurora_sg.id
  from_port   = 5432
  ip_protocol = "tcp"
  to_port     = 5432
}


# Create a aurora master username and passwords as a secret as secret manager to pass it to the RDS Proxy in next step
resource "aws_secretsmanager_secret" "aurora_master_secret" {
  name = "aurora-master-credentials-1"
}

resource "aws_secretsmanager_secret_version" "aurora_master_secret_version" {
  secret_id = aws_secretsmanager_secret.aurora_master_secret.id

  secret_string = jsonencode({
    username = aws_rds_cluster.online-ticketing-system.master_username
    password = aws_rds_cluster.online-ticketing-system.master_password
  })
}



# Create an IAM Policy for RDS Proxy to acceess secret manager secret

resource "aws_iam_policy" "rds_proxy_allow_secret_manager_connection" {
  name        = "rds-proxy-allow-secret-manager-connection"
  path        = "/"
  description = "This is an Allow Policy for RDS Proxy to allow to connect to Secret Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Resource = aws_secretsmanager_secret.aurora_master_secret.arn
      }
    ]
  })
}


# Attach the policy to the existing RDS Proxy Role
resource "aws_iam_role_policy_attachment" "attach_rds_proxy_allow_secret_manager_access" {
  role       = aws_iam_role.rds_proxy_role.name
  policy_arn = aws_iam_policy.rds_proxy_allow_secret_manager_connection.arn
}

# Create a RDS Proxy with end to end IAM Authentication so that db credentials are not needed in Secrets Manager
resource "aws_db_proxy" "rds_proxy" {
  name                   = "rds-proxy"
  debug_logging          = false
  engine_family          = "POSTGRESQL"
  idle_client_timeout    = 1200
  require_tls            = true
  role_arn               = aws_iam_role.rds_proxy_role.arn
  vpc_security_group_ids = [aws_security_group.rds_proxy_sg.id]
  vpc_subnet_ids         = var.subnet_group
  default_auth_scheme = "IAM_AUTH"

  auth {
    description = "End to End IAM Authentication"
    iam_auth    = "REQUIRED"
    secret_arn  = aws_secretsmanager_secret.aurora_master_secret.arn
  }

  tags = {
    Name = "RDS_Proxy"
    Key  = "RDS_Proxy"
  }
}


# Create a RDS Proxy Target Group and Target to the Aurora DB Cluster

resource "aws_db_proxy_default_target_group" "rds_proxy_target_group" {
  db_proxy_name = aws_db_proxy.rds_proxy.name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 100
    max_idle_connections_percent = 50
    session_pinning_filters      = ["EXCLUDE_VARIABLE_SETS"]
  }

  lifecycle {
    replace_triggered_by = [aws_db_proxy.rds_proxy.id]
  }
}

resource "aws_db_proxy_target" "rds_proxy_target" {
  db_cluster_identifier  = aws_rds_cluster.online-ticketing-system.id
  db_proxy_name          = aws_db_proxy.rds_proxy.name
  target_group_name      = aws_db_proxy_default_target_group.rds_proxy_target_group.name

  lifecycle {
    replace_triggered_by = [aws_db_proxy.rds_proxy.id]
  }
}


