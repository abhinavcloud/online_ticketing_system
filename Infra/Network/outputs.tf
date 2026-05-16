output "subnet_group" {
    value = aws_subnet.private_subnets[each.key]
}