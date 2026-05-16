
#Creating an Aurora Serverless DB Cluster
resource "aws_rds_cluster" "online-ticketing-system" {
  cluster_identifier = "online-ticketing-system"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  ngine_version     = "17.7"
  database_name      = "online-ticketing-system"
  master_username    = "test" # to be changed later as secret
  master_password    = "must_be_eight_characters" # to be changed later as secret
  storage_encrypted  = true

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
  promotion_tier = 0
}

# Creating the reader instance in AZ 2
resource "aws_rds_cluster_instance" "reader_instance_01" {
  cluster_identifier = aws_rds_cluster.online-ticketing-system.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.online-ticketing-system.engine
  engine_version     = aws_rds_cluster.online-ticketing-system.engine_version
  availability_zone = var.availability_zones[1]
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
  promotion_tier = 1
  depends_on = [aws_rds_cluster_instance.writer_instance]
}