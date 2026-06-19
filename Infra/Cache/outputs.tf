output "browse_cache_arn" {
    value = aws_elasticache_replication_group.browse_cache.arn
}


output "browse_cache_endpoint" {
  value = aws_elasticache_replication_group.browse_cache.primary_endpoint_address
}


output "browse_cache_port" {
  value = aws_elasticache_replication_group.browse_cache.port
}


output "browse_cache_name" {
  value = aws_elasticache_replication_group.browse_cache.replication_group_id
}


#output "active_users_arn" {
#    value = aws_elasticache_replication_group.active_users.arn
#   
#}


#output "active_users_cache_endpoint" {
#  value = aws_elasticache_replication_group.active_users.primary_endpoint_address
#}

#output "active_users_cache_port" {
#  value = aws_elasticache_replication_group.active_users.port
#}

#output "active_users_cache_name" {
#  value = aws_elasticache_replication_group.active_users.replication_group_id
#}



#output "seat_lock_arn" {
#    value = aws_elasticache_replication_group.seat_lock.arn
#}



#output "seat_lock_cache_endpoint" {
#  value = aws_elasticache_replication_group.seat_lock.primary_endpoint_address
#}

#output "seat_lock_cache_port" {
#  value = aws_elasticache_replication_group.seat_lock.port
#}

#output "seat_lock_cache_name" {
#  value = aws_elasticache_replication_group.seat_lock.replication_group_id
#}


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
