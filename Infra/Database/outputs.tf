
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

output "db_cluster_security_group" {
  value = aws_security_group.aurora_sg.id
}

output "secret_manager_access_policy" {
  value = aws_iam_policy.lambda_allow_secret_manager_connection.arn
}