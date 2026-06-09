output "db_proxy_arn" {
    value = aws_db_proxy.rds_proxy.arn
}


output "db_proxy_endpoint" {
  value = aws_db_proxy.rds_proxy.endpoint
}

output "db_proxy_resource_id" {
  value = aws_db_proxy.rds_proxy.id  
}

output "db_proxy_security_group" {
    value = aws_security_group.rds_proxy_sg.id
}

output "db_cluster_endpoint" {
  value = aws_rds_cluster.online-ticketing-system.endpoint
}

output "db_cluster_port" {
  value = aws_rds_cluster.online-ticketing-system.port
}

output "db_name" {
  value = aws_rds_cluster.online-ticketing-system.database_name
}


output "db_port" {
  value = aws_rds_cluster.online-ticketing-system.port
}


output "db_cluster_resource_id" {
  value = aws_rds_cluster.online-ticketing-system.cluster_resource_id
}
