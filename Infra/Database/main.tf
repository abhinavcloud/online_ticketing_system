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

#Creating an Ingress rule to port 5432 to Aurora Cluster
resource "aws_vpc_security_group_ingress_rule" "aurora_sg_ingress_rule" {
  security_group_id = aws_security_group.aurora_sg.id
  cidr_ipv4         = aws_vpc.main.cidr_block
  from_port         = 5432
  ip_protocol       = "tcp"
  to_port           = 5432
}

# Egress rule is not needed


#Creating an Aurora Serverless DB Cluster
resource "aws_rds_cluster" "online-ticketing-system" {
  cluster_identifier = "online-ticketing-system"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = "17.7"
  database_name      = "online-ticketing-system"
  master_username    = "test" # to be changed later as secret
  master_password    = "must_be_eight_characters" # to be changed later as secret
  storage_encrypted  = true
  db_subnet_group_name = aws_db_subnet_group.aurora_db_subnet_group.name
  enable_http_endpoint = false
  vpc_security_group_ids = [aws_security_group.aurora_sg]
  iam_database_authentication_enabled = true
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
  name        = "rds_proxy_allow_aurora_db_connection"
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
                "arn:aws:rds-db:us-east-2:111122223333:dbuser:cluster-ABCDEFGHIJKL01234/db_user"
            ]
        }
    ]
})
}

# Create an IAM role for RDS Proxy to connect to Aurora DB via IAM Authentication
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
  name               = "test-role"
  assume_role_policy = data.aws_iam_policy_document.rds_proxy_assume_role.json
}

# Attach the aurora db connect policy to the rds proxy role
resource "aws_iam_role_policy_attachment" "attach_rds_proxy_allow_aurora_db_connection" {
  role       = aws_iam_role.rds_proxy_role.name
  policy_arn = aws_iam_policy.rds_proxy_allow_aurora_db_connection.arn
}



# Create a security group for RDS Proxy to Allow Egress to Aurora DB Cluster and Ingress from Lambda



# Create a RDS Proxy with end to end IAM Authentication so that db credentials are not needed in Secrets Manager



# Create a proxy endpoint for Lambdas to connect to


