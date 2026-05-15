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
  availability_zone   = data.aws_availability_zones.available.names[0]
  depends_on = [aws_vpc.vpc]
    
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
  for_each = aws_subnet.private_subnets
  vpc_id = aws_vpc.vpc.id

  tags = merge(
    var.common_tags,
    {
    Name        = "${each.key}"
    Region = var.Region
    AvailabilityZones = var.az_name_tag
    } 
  )
}