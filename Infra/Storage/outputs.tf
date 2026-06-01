output "bucket_name" {
  description = "S3 bucket name for the website"
  value       = aws_s3_bucket.site.bucket
}

output "bucket_arn" {
  description = "ARN of the S3 website bucket"
  value       = aws_s3_bucket.site.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name used by CloudFront as origin"
  value       = aws_s3_bucket.site.bucket_regional_domain_name
}