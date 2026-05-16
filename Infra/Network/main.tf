# Virtual Private Network

resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    var.common_tags,
    {
    Name        = "${var.vpc_name}"
    Region = var.Region
    AvailabilityZones = var.az_name_tag
    } 
  )
  
}

# Subnets
resource "aws_subnet" "private_subnets" {
  for_each = var.private_subnets # using for_each to create 3 subnets for each item in the private subnet list variable
  vpc_id              = aws_vpc.vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr, 8, each.value + 100)
  availability_zone   = var.availability_zone[each.value]
    
  tags = merge(
    var.common_tags,
    {
    Name        = "${each.key}"
    Region = var.Region
    AvailabilityZones = var.az_name_tag
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
    Region = var.Region
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