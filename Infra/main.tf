data "aws_region" "current" {}

data "aws_availability_zones" "az" {
  state = "available"
}


module "Network" {

    source = "./Network/"
    common_tags = local.common_tags
    vpc_cidr    = var.vpc_cidr
    az_name_tag = join(",", data.aws_availability_zones.available.names)
    Region = data.aws_region.current.name

}