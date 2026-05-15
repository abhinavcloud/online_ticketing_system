output "availilbility_zones_id" {
    value = data.aws_availability_zones.az.id
}

output "availilbility_zones_zoneids" {
    value = data.aws_availability_zones.az.zone_ids
}

output "availilbility_zones_names" {
    value = data.aws_availability_zones.az.names
}
