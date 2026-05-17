data "aws_region" "current" {}

data "aws_availability_zones" "az" {
  state = "available"
}


module "Network" {

    source = "./Network/"
    common_tags = local.common_tags
    vpc_cidr    = var.vpc_cidr
    region = data.aws_region.current.id
    availability_zones   = data.aws_availability_zones.az.names
}


module "Database" {

    source = "./Database/"
    availability_zones   = data.aws_availability_zones.az.names
    subnet_group = [module.Network.subnet_01, module.Network.subnet_02, module.Network.subnet_03]
    vpc_id = module.Network.vpc_id
    region = data.aws_region.current.id
    account_id = var.account_id
    master_username = var.master_username
    master_password = var.master_password
    referenced_security_group_id = module.Compute.lambda_sg

}

module "Compute" {
    source = "./Compute/"
    db_proxy_id = module.Database.db_proxy_id
    region = data.aws_region.current.id
    account_id = var.account_id
    vpc_id = module.Network.vpc_id

}

module "Cache" {
    source = "./Cache/"
    vpc_id = module.Network.vpc_id
    referenced_security_group_id = module.Compute.lambda_sg
    subnet_group = [module.Network.subnet_01, module.Network.subnet_02, module.Network.subnet_03]
}