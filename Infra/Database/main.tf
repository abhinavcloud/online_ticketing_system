resource "aws_rds_cluster" "example" {
  cluster_identifier = "example"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = "13.6"
  database_name      = "test"
  master_username    = "test"
  master_password    = "must_be_eight_characters"
  storage_encrypted  = true

  serverlessv2_scaling_configuration {
    max_capacity             = 1.0
    min_capacity             = 0.0
    seconds_until_auto_pause = 600
  }
}

resource "aws_rds_cluster_instance" "writer_instance" {
  cluster_identifier = aws_rds_cluster.example.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.example.engine
  engine_version     = aws_rds_cluster.example.engine_version
  availibility_zone = 
  promotion_tier = 0
}

resource "aws_rds_cluster_instance" "reader_instance_01" {
  cluster_identifier = aws_rds_cluster.example.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.example.engine
  engine_version     = aws_rds_cluster.example.engine_version
  availibility_zone = 
  promotion_tier = 1


}

resource "aws_rds_cluster_instance" "reader_instance_02" {
  cluster_identifier = aws_rds_cluster.example.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.example.engine
  engine_version     = aws_rds_cluster.example.engine_version
  availibility_zone = 
  promotion_tier = 1
}