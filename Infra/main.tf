data "aws_region" "current" {}

data "aws_availability_zones" "az" {
  state = "available"
}


# Create a Security Group for Lambda 
# Defining this out of Compute Module to avoid circular dependency between lambda, aurora and elasticache security groups
resource "aws_security_group" "lambda_sg" {
  name        = "lambda-sg"
  description = "Allow TLS inbound traffic from lambda"
  vpc_id      = module.Network.vpc_id

  tags = {
    Application = "Lambda"
    Type = "Security_Group"
  }
}

module "Network" {

    source = "./Network/"
    common_tags = local.common_tags
    vpc_cidr    = var.vpc_cidr
    region = data.aws_region.current.id
    availability_zones   = data.aws_availability_zones.az.names
    referenced_security_group_id = aws_security_group.lambda_sg.id

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




module "Compute" {
    source = "./Compute/"
    
    #Network
    region = data.aws_region.current.id
    account_id = var.account_id
    vpc_id = module.Network.vpc_id
    subnet_group = [module.Network.subnet_01, module.Network.subnet_02, module.Network.subnet_03]
    
    # DB Proxy and Cache ARN
    db_proxy_id = split(":", module.Database.db_proxy_arn)[6]
    browse_cache = module.Cache.serverless_cache_browse
    active_user_lock_cache= module.Cache.serverless_active_user_lock
    seat_lock_cache = module.Cache.serverless_seat_lock
    user = module.Cache.user
    
    # Security Groups
    security_group_id = aws_security_group.lambda_sg.id
    db_proxy_security_group = module.Database.db_proxy_security_group
    elasticache_security_group = module.Cache.elasticache_security_group
    vpc_endpoint_security_group = module.Network.vpc_endpoint_sg

    
    # DB Proxy Details    
    db_proxy_endpoint = module.Database.db_proxy_endpoint
    db_port           = module.Database.db_port
    db_name           = module.Database.db_name
    db_user           = var.app_db_user   # define in Infra/variables.tf

    # Cache User 
    elasticache_user_id   = module.Cache.elasticache_user_id
    
    # Browse Cache detail
    browse_cache_endpoint = module.Cache.browse_cache_endpoint
    browse_cache_port     = module.Cache.browse_cache_port
    browse_cache_name     = "browse-cache" # must match actual serverless cache name
    browse_cache_ttl_seconds = 30
    
    #Active User Cache detail
    active_users_cache_endpoint = module.Cache.active_users_cache_endpoint
    active_users_cache_port     = module.Cache.active_users_cache_port
    active_users_cache_name     = module.Cache.active_users_cache_name

    #Seat Lock Cache
    seat_lock_cache_endpoint =  module.Cache.seat_lock_cache_endpoint
    seat_lock_cache_port  = module.Cache.seat_lock_cache_port
    seat_lock_cache_name = module.Cache.seat_lock_cache_name

    #Notification ARN
    notification_topic_arn = module.Notification.ticketing_notifications_topic_arn
  
}

module "Cache" {
    source = "./Cache/"
    vpc_id = module.Network.vpc_id
    referenced_security_group_id = aws_security_group.lambda_sg.id
    subnet_group = [module.Network.subnet_01, module.Network.subnet_02, module.Network.subnet_03]
}

module "Notification" {
    source = "./Notification/"
    notification_email = var.notification_email
}


module "APIGateway" {
    source = "./APIGateway/"
    browse_service_arn = module.Compute.browse_service_arn
    queue_service_arn = module.Compute.queue_service_arn
    seat_availability_service_arn = module.Compute.seat_availability_service_arn
    reservation_service_arn = module.Compute.reservation_service_arn
    payment_service_arn = module.Compute.payment_service_arn
    confirmation_service_arn = module.Compute.confirmation_service_arn
    browse_service_name = module.Compute.browse_service_name
    queue_service_name = module.Compute.queue_service_name
    seat_availability_service_name = module.Compute.seat_availability_service_name
    reservation_service_name = module.Compute.reservation_service_name
    payment_service_name = module.Compute.payment_service_name
    confirmation_service_name = module.Compute.confirmation_service_name
    user_pool_arn = module.Authentication.google_user_pool_arn

}

module "Authentication" {
    source = "./Authentication/"
    
    app_name = var.app_name
    root_domain = var.root_domain
    client_id = var.client_id
    client_secret = var.client_secret

}