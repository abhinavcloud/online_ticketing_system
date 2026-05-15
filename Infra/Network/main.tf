resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    var.common_tags,
    {
    Name        = "${var.vpc_name}-workspace-${terraform.workspace}"
    Region = var.Region
    AvailabilityZones = var.az_name_tag
    } 
  )
  
  
}