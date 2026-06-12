output "subnet_01" {
    value = aws_subnet.private_subnets["private_subnet_1"].id
}

output "subnet_02" {
    value = aws_subnet.private_subnets["private_subnet_2"].id
}

output "subnet_03" {
    value = aws_subnet.private_subnets["private_subnet_3"].id
}

output "vpc_id" {
    value = aws_vpc.vpc.id
}

output "vpc_endpoint_kms_sg" {
    value = aws_security_group.kms_vpce_sg.id
    
}

output "vpc_endpoint_sns_sg" {
    value = aws_security_group.sns_vpce_sg.id
}

