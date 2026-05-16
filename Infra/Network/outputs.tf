output "subnet_01" {
    value = aws_subnet.private_subnets[0].name
}

output "subnet_02" {
    value = aws_subnet.private_subnets[1].name
}

output "subnet_03" {
    value = aws_subnet.private_subnets[2].name
}