output "serverless_cache_browse" {
    value = aws_elasticache_serverless_cache.browse_cache.arn
}

output "serverless_active_user_lock" {
    value = aws_elasticache_serverless_cache.active_users.arn
}

output "serverless_seat_lock" {
    value = aws_elasticache_serverless_cache.seat_lock.arn
}

output "user" {
    value = aws_elasticache_user.elasticache_user.arn
}

output "elasticache_security_group" {
    value = aws_security_group.elasticache_sg.id
}