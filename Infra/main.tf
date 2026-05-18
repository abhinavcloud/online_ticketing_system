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
    referenced_security_group_id = aws_security_group.lambda_sg.id

}


# Create a Security Group for Lambda 
resource "aws_security_group" "lambda_sg" {
  name        = "lambda-sg"
  description = "Allow TLS inbound traffic from lambda"
  vpc_id      = module.Network.vpc_id

  tags = {
    Application = "Elasticache"
    Type = "Security_Group"
  }
}

module "Compute" {
    source = "./Compute/"
    db_proxy_id = split(":", module.Database.db_proxy_arn)[6]
    region = data.aws_region.current.id
    account_id = var.account_id
    vpc_id = module.Network.vpc_id
    browse_cache = module.Cache.serverless_cache_browse
    active_user_lock_cache= module.Cache.serverless_active_user_lock
    seat_lock_cache = module.Cache.serverless_seat_lock
    user = module.Cache.user
    security_group_id = aws_security_group.lambda_sg.id
    db_proxy_security_group = module.Database.db_proxy_security_group
    elasticache_security_group = module.Cache.elasticache_security_group

}

module "Cache" {
    source = "./Cache/"
    vpc_id = module.Network.vpc_id
    referenced_security_group_id = aws_security_group.lambda_sg.id
    subnet_group = [module.Network.subnet_01, module.Network.subnet_02, module.Network.subnet_03]
}