data "aws_caller_identity" "current" {}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}


data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}


locals {
  apigw_invoke_url = trimsuffix(var.base_url, "/")

  apigw_invoke_no_scheme = replace(local.apigw_invoke_url, "https://", "")
  apigw_domain_name      = split("/", local.apigw_invoke_no_scheme)[0]
  apigw_stage_name       = split("/", local.apigw_invoke_no_scheme)[1]
  apigw_origin_path      = "/${local.apigw_stage_name}"
}


resource "aws_cloudfront_origin_access_control" "site_oac_ticketing" {
  name                              = "ticketing-site-oac"
  description                       = "OAC for private S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "CloudFront for online ticketing system frontend and API proxy"
  price_class         = "PriceClass_100"

  aliases = var.enable_custom_domain ? [var.root_domain] : []

  # -------------------------------------------------------------------
  # Origin 1: Private S3 bucket for static frontend assets and HTML pages
  # -------------------------------------------------------------------
  origin {
    domain_name              = var.bucket_regional_domain_name
    origin_id                = "s3-${var.bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.site_oac.id
  }

  # -------------------------------------------------------------------
  # Origin 2: API Gateway for all backend API routes under /v1/*
  # base_url is expected to be:
  # https://<rest_api_id>.execute-api.<region>.amazonaws.com/<stage>
  # local.apigw_domain_name  -> <rest_api_id>.execute-api.<region>.amazonaws.com
  # local.apigw_origin_path  -> /<stage>
  # -------------------------------------------------------------------
  origin {
    domain_name = local.apigw_domain_name
    origin_id   = "apigw-ticketing"
    origin_path = local.apigw_origin_path

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # -------------------------------------------------------------------
  # Ordered behavior: all backend API traffic goes to API Gateway
  # Online ticketing system APIs are under /v1/*
  # -------------------------------------------------------------------
  ordered_cache_behavior {
    path_pattern           = "/v1/*"
    target_origin_id       = "apigw-ticketing"
    viewer_protocol_policy = "redirect-to-https"

    # Backend supports GET/POST and potentially OPTIONS for browser flows.
    # Keep the full standard dynamic set to avoid future route-method issues.
    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    compress = true

    # Dynamic API content should not be cached at the edge.
    cache_policy_id = data.aws_cloudfront_cache_policy.caching_disabled.id

    # Forward viewer request details needed by API Gateway/backend while excluding
    # the viewer Host header so CloudFront sets the correct API Gateway origin host.
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # -------------------------------------------------------------------
  # Default behavior: static frontend from S3
  # -------------------------------------------------------------------
  default_cache_behavior {
    target_origin_id       = "s3-${var.bucket_name}"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    compress        = true
    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  # -------------------------------------------------------------------
  # Viewer certificate
  # If enable_custom_domain = true, ACM cert must be in us-east-1 for CloudFront
  # -------------------------------------------------------------------
  viewer_certificate {
    cloudfront_default_certificate = var.enable_custom_domain ? false : true
    acm_certificate_arn            = var.enable_custom_domain ? var.acm_cert : null
    ssl_support_method             = var.enable_custom_domain ? "sni-only" : null
    minimum_protocol_version       = var.enable_custom_domain ? "TLSv1.2_2021" : null
  }

  # -------------------------------------------------------------------
  # No geo restriction
  # -------------------------------------------------------------------
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
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


