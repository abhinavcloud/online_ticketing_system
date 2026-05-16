data "aws_region" "current" {}

data "aws_availability_zones" "az" {
  state = "available"
}


module "Network" {

    source = "./Network/"
    common_tags = local.common_tags
    vpc_cidr    = var.vpc_cidr
    Region = data.aws_region.current.name
    availability_zones   = data.aws_availability_zones.az.names



}