variable "availability_zones" {
  description = "list of availbility zones"
  type = list(string)
}

variable "subnet_group" {
    description = "list of subnet groups"
    type = list(string)
}