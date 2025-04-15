data "aws_caller_identity" "current" {}

provider "aws" {
  region  = "us-east-1"
  alias   = "us_east_1"
  profile = "SandboxTsedey"
}

# S3 bucket for frontend
resource "aws_s3_bucket" "frontend" {
  bucket = "movie-app-projekt-tsedey"
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  depends_on = [aws_cloudfront_distribution.frontend]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontAccess"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.frontend.id}"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

# ACM certificate for SSL
resource "aws_acm_certificate" "frontend" {
  provider          = aws.us_east_1
  domain_name       = "tsedey.mytestdomain.io"  
  validation_method = "DNS"
}

# Automatically create the DNS validation record for ACM certificate
resource "aws_route53_record" "frontend_validation" {
  provider = aws
  for_each = { for option in aws_acm_certificate.frontend.domain_validation_options : option.resource_record_name => option }

  zone_id = "Z09217081I7Y8I53ZZFA3"  
  name     = each.value.resource_record_name
  type     = each.value.resource_record_type
  ttl      = 60
  records  = [each.value.resource_record_value]
}

provider "aws" {
  region = "us-east-1"
}

# CloudFront Origin Request Policy (Allow Authorization Header)
resource "aws_cloudfront_origin_request_policy" "allow_auth_header" {
  name        = "AllowAuthorizationHeader"

  headers_config {
    headers {
      items = ["Authorization"]
    }
  }
}

# CloudFront Response Headers Policy (Allow CORS for Frontend)
resource "aws_cloudfront_response_headers_policy" "cors" {
  name    = "AllowCORSForFrontend"
  
  cors_config {
    access_control_allow_origins {
      items = ["*"]
    }
    access_control_allow_origins {
      allowed_origins = ["*"]
    }

    access_control_allow_headers {
      items = ["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key"]
    }

  access_control_allow_methods {
      allowed_methods = ["OPTIONS", "GET", "POST", "PUT", "DELETE"]
    }
  access_control_expose_headers {
      items = ["X-Amz-Date", "Authorization"]
    }

    access_control_max_age_sec = 600
    origin_override            = true
  }
}

# CloudFront Cache Policy (Disable Caching)
resource "aws_cloudfront_cache_policy" "caching_disabled" {
  name               = "CachingDisabled"
  comment            = "Disable caching for API responses"
  default_ttl        = 0
  max_ttl            = 0
  min_ttl            = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    query_strings_config {
      query_string_behavior = "none"
    }

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }
  }
}

# CloudFront Distribution for frontend (S3 origin and CORS handling)
resource "aws_cloudfront_distribution" "frontend" {
  origin {
    domain_name = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id   = "S3-movie-app-frontend"
  }

  enabled             = true
  is_ipv6_enabled     = false
  default_root_object = "index.html"

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.frontend.arn
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  default_cache_behavior {
    target_origin_id       = "S3-movie-app-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    
    cache_policy_id        = aws_cloudfront_cache_policy.caching_disabled.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.cors.id

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  price_class = "PriceClass_100"
}

# Route 53 for custom domain
resource "aws_route53_record" "frontend" {
  zone_id = "Z09217081I7Y8I53ZZFA3"  
  name    = "tsedey.mytestdomain.io"  
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_cloudfront_origin_access_control" "frontend_oac" {
  name                              = "FrontendOAC"
  description                       = "OAC for S3 frontend bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
