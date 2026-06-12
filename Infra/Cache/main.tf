# Creating a User with IAM Authentication
resource "aws_elasticache_user" "elasticache_user" {
  user_id       = "test-user-id"
  user_name     = "test-user-id"
  access_string = "on ~* +@all"
  engine        = "valkey"

  authentication_mode {
    type = "iam"
  }
}

# Create an Elasticache User Group
resource "aws_elasticache_user_group" "elasticache_user_group" {
  engine        = "valkey"
  user_group_id = "user-group-id"
  user_ids      = [aws_elasticache_user.elasticache_user.user_id]
  depends_on = [aws_elasticache_user.elasticache_user]
}

# Create an Elasticache Security Group
resource "aws_security_group" "elasticache_sg" {
  name        = "elasticache-sg"
  description = "Allow TLS inbound traffic from lambda"
  vpc_id      = var.vpc_id

  tags = {
    Application = "Elasticache"
    Type = "Security_Group"
  }
}


# Create an Elasticache Security Group Ingress Rule
# Creating an Ingress rule from lambda security group to elasticache  security group
resource "aws_vpc_security_group_ingress_rule" "elasticache_sg_ingress_rule" {
  security_group_id = aws_security_group.elasticache_sg.id
  referenced_security_group_id = var.referenced_security_group_id
  from_port         = 6379
  ip_protocol       = "tcp"
  to_port           = 6379
}


# Create an Elasticache Serverless cluster for Browse Cache
#resource "aws_elasticache_serverless_cache" "browse_cache" {
#  engine = "valkey"
#  name   = "browse-cache"
#  cache_usage_limits {
#    data_storage {
#      maximum = 10
#      unit    = "GB"
#    }
#    ecpu_per_second {
#      maximum = 5000
#    }
#  }
#  daily_snapshot_time      = "09:00"
#  description              = "Elasticache for Browsing"
#  #kms_key_id               = aws_kms_key.test.arn
#  major_engine_version     = "9"
#  snapshot_retention_limit = 1
#  security_group_ids       = [aws_security_group.elasticache_sg.id]
#  subnet_ids               = var.subnet_group
#  user_group_id = aws_elasticache_user_group.elasticache_user_group.id
#}

#Elasticache Subnet Group
resource "aws_elasticache_subnet_group" "elasticache_subnet" {
  name       = "elasticache-subnet-group"
  subnet_ids = var.subnet_group
}

# Create an Elasticache Provisoned cluster for Browse Cache

resource "aws_elasticache_replication_group" "browse_cache" {
  replication_group_id = "browse-cache"
  description          = "Highly available browse cache using Valkey across 3 AZs"

  engine               = "valkey"
  engine_version       = "9.0"
  node_type            = "cache.t4g.micro"

 # Single node
  num_cache_clusters          = 1
  preferred_cache_cluster_azs = var.preferred_cache_cluster_azs

#  automatic_failover_enabled = true
#  multi_az_enabled           = true

  subnet_group_name  = aws_elasticache_subnet_group.elasticache_subnet.id
  security_group_ids = [aws_security_group.elasticache_sg.id]

  parameter_group_name       = "default.valkey9"
  snapshot_retention_limit   = 1
  apply_immediately          = true
  auto_minor_version_upgrade = true

 tags = {
   Name = "browse-cache-cache"
 }
}



# Create an Elasticache Serverless cluster for Active Users
resource "aws_elasticache_serverless_cache" "active_users" {
  engine = "valkey"
  name   = "active-users"
  cache_usage_limits {
    data_storage {
      maximum = 10
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = 5000
    }
  }
  daily_snapshot_time      = "09:00"
  description              = "Elasticache for holding Active Users"
  #kms_key_id               = aws_kms_key.test.arn
  major_engine_version     = "9"
  snapshot_retention_limit = 1
  security_group_ids       = [aws_security_group.elasticache_sg.id]
  subnet_ids               = var.subnet_group
  user_group_id = aws_elasticache_user_group.elasticache_user_group.id
}


# Create an Elasticache Serverless cluster for Seat Locks
resource "aws_elasticache_serverless_cache" "seat_lock" {
  engine = "valkey"
  name   = "seat-lock"
  cache_usage_limits {
    data_storage {
      maximum = 10
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = 5000
    }
  }
  daily_snapshot_time      = "09:00"
  description              = "Elasticache for holding locked seats"
  #kms_key_id               = aws_kms_key.test.arn
  major_engine_version     = "9"
  snapshot_retention_limit = 1
  security_group_ids       = [aws_security_group.elasticache_sg.id]
  subnet_ids               = var.subnet_group
  user_group_id = aws_elasticache_user_group.elasticache_user_group.id
}