data "aws_caller_identity" "current" {}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}


data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}


locals {
  apigw_invoke_url = trimsuffix(var.base_url, "/")

  apigw_invoke_no_scheme = replace(local.apigw_invoke_url, "https://", "")
  apigw_domain_name      = split("/", local.apigw_invoke_no_scheme)[0]
  apigw_stage_name       = split("/", local.apigw_invoke_no_scheme)[1]
  apigw_origin_path      = "/${local.apigw_stage_name}"
}


resource "aws_cloudfront_origin_access_control" "site_oac" {
  name                              = "shorturl-site-oac"
  description                       = "OAC for private S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "CloudFront for shorturl landing page"
  aliases = var.enable_custom_domain ? [var.root_domain] : []

  origin {
    domain_name              = var.bucket_regional_domain_name
    origin_id                = "s3-${var.bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.site_oac.id
  }
  
  origin {
    domain_name = local.apigw_domain_name
    origin_id   = "apigw-shorturl"
    origin_path = local.apigw_origin_path

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  
  ordered_cache_behavior {
    path_pattern           = "/r/*"
    target_origin_id       = "apigw-shorturl"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    compress        = true

    cache_policy_id = data.aws_cloudfront_cache_policy.caching_disabled.id
  }



  default_cache_behavior {
    target_origin_id       = "s3-${var.bucket_name}"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    compress        = true
    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  
viewer_certificate {
  cloudfront_default_certificate = var.enable_custom_domain ? false : true

  acm_certificate_arn = var.enable_custom_domain ? var.acm_cert : null

  ssl_support_method = var.enable_custom_domain ? "sni-only" : null

  minimum_protocol_version = var.enable_custom_domain ? "TLSv1.2_2021" : null
}


  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  price_class = "PriceClass_100"
}

# Bucket policy to allow ONLY this CloudFront distribution to read objects
data "aws_iam_policy_document" "site_bucket_policy" {
  statement {
    sid    = "AllowCloudFrontReadOnly"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${var.bucket_arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values = [
        "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.site.id}"
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = var.bucket_name
  policy = data.aws_iam_policy_document.site_bucket_policy.json
}


