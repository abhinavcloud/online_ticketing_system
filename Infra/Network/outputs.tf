output "subnet_01" {
    value = aws_subnet.private_subnets[0].id
}

output "subnet_02" {
    value = aws_subnet.private_subnets[1].id
}

output "subnet_03" {
    value = aws_subnet.private_subnets[2].id
}