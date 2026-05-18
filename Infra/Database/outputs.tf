output "db_proxy_arn" {
    value = aws_db_proxy.rds_proxy.arn
}

output "db_proxy_security_group" {
    value = aws_security_group.rds_proxy_sg.id
}