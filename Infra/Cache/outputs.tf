output "serverless_cache_browse" {
    value = aws_elasticache_replication_group.browse_cache.arn
}


output "browse_cache_endpoint" {
  value = aws_elasticache_replication_group.browse_cache.endpoint[0].address
}


output "browse_cache_port" {
  value = aws_elasticache_replication_group.browse_cache.endpoint[0].port
}


output "browse_cache_name" {
  value = aws_elasticache_replication_group.browse_cache.name
}


output "serverless_active_user_lock" {
    value = aws_elasticache_serverless_cache.active_users.arn

    
}


output "active_users_cache_endpoint" {
  value = aws_elasticache_serverless_cache.active_users.endpoint[0].address
}

output "active_users_cache_port" {
  value = aws_elasticache_serverless_cache.active_users.endpoint[0].port
}

output "active_users_cache_name" {
  value = aws_elasticache_serverless_cache.active_users.name
}



output "serverless_seat_lock" {
    value = aws_elasticache_serverless_cache.seat_lock.arn
}



output "seat_lock_cache_endpoint" {
  value = aws_elasticache_serverless_cache.seat_lock.endpoint[0].address
}

output "seat_lock_cache_port" {
  value = aws_elasticache_serverless_cache.seat_lock.endpoint[0].port
}

output "seat_lock_cache_name" {
  value = aws_elasticache_serverless_cache.seat_lock.name
}


output "user" {
    value = aws_elasticache_user.elasticache_user.arn
}


output "elasticache_user_id" {
  value = aws_elasticache_user.elasticache_user.user_id
}

output "elasticache_user_name" {
  value = aws_elasticache_user.elasticache_user.user_name
}



output "elasticache_security_group" {
    value = aws_security_group.elasticache_sg.id
}
