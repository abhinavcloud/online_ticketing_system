output "subnet_01" {
    value = aws_subnet.private_subnets["private_subnet_1"].id
}

output "subnet_02" {
    value = aws_subnet.private_subnets["private_subnet_2"].id
}

output "subnet_03" {
    value = aws_subnet.private_subnets["private_subnet_3"].id
}