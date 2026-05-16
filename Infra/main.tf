data "aws_region" "current" {}

data "aws_availability_zones" "az" {
  state = "available"
}


module "Network" {

    source = "./Network/"
    common_tags = local.common_tags
    vpc_cidr    = var.vpc_cidr
    Region = data.aws_region.current.id
    availability_zones   = data.aws_availability_zones.az.names
}


module "Database" {

    source = "./Database/"
    availability_zones   = data.aws_availability_zones.az.names
    subnet_group = [var.subnet_01, var.subnet_02, var.subnet_03]
}