# Virtual Private Network

resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    var.common_tags,
    {
    Name        = "${var.vpc_name}"
    region = var.region
    } 
  )
  
}

# Subnets
resource "aws_subnet" "private_subnets" {
  for_each = var.private_subnets # using for_each to create 3 subnets for each item in the private subnet list variable
  vpc_id              = aws_vpc.vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, each.value + 100)
  availability_zone   = var.availability_zones[each.value]
    
  tags = merge(
    var.common_tags,
    {
    Name        = "${each.key}"
    region = var.region
    } 
  )
}

# Route Tables
resource "aws_route_table" "private_route_table" {
  for_each = var.private_subnets
  vpc_id = aws_vpc.vpc.id

  tags = merge(
    var.common_tags,
    {
    Name        = "${each.key}"
    region = var.region
    } 
  )
}

# Map route tables to subnets.
resource "aws_route_table_association" "private" {
  for_each = var.private_subnets
  route_table_id = aws_route_table.private_route_table[each.key].id
  subnet_id      = aws_subnet.private_subnets[each.key].id
  
}

# Create an internet gateway for the VPC
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}

# Create a regional NAT Gatway
resource "aws_nat_gateway" "regional_nat" {
  vpc_id            = aws_vpc.vpc.id
  availability_mode = "regional"
}

# Create a route for each route table and associate regional NAT Gateway to it
resource "aws_route" "private_route" {
  for_each = var.private_subnets
  route_table_id = aws_route_table.private_route_table[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.regional_nat.id
}

# Create a VPC Endpoint for Lambda to connect to KMS

## Create a security group for VPC Endpoint with Lambda SG as Ingress and Any as Egress

resource "aws_security_group" "kms_vpce_sg" {
  name        = "kms-vpce-sg"
  description = "Security group for KMS VPC Interface Endpoint"
  vpc_id      = aws_vpc.vpc.id

  tags = {
    Name = "kms-vpce-sg"
 
  }
}


resource "aws_vpc_security_group_ingress_rule" "kms_vpce_ingress_from_lambda" {
  security_group_id            = aws_security_group.kms_vpce_sg.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = var.referenced_security_group_id
  description                  = "Allow Lambda SG to reach KMS VPCE on 443"
}



resource "aws_vpc_security_group_egress_rule" "kms_vpce_egress_all" {
  security_group_id = aws_security_group.kms_vpce_sg.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow VPCE responses"
}



resource "aws_vpc_endpoint" "kms" {
  vpc_id            = aws_vpc.vpc.id
  service_name      = "com.amazonaws.${var.region}.kms"
  vpc_endpoint_type = "Interface"
  subnet_ids =  local.private_subnet_ids

  security_group_ids = [
    aws_security_group.kms_vpce_sg.id,
  ]

  private_dns_enabled = true

  tags = {
    Name = "VPC_Endpoint_from_Lambda_to_KMS"
    Type = "VPC_Endpoint"
  }
}