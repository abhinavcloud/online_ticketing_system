variable "vpc_id" {
    description = "VPC Id"
    type = string
}

variable "referenced_security_group_id" {
    description = "Lambda Security Group as Ingress to Elasticache Security Group"
    type = string
}

variable "subnet_group" {
    description = "list of subnet groups"
    type = list(string)
}
