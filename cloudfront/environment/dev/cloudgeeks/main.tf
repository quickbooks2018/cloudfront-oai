terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}
provider "aws" {
  region = "us-east-1"
}
terraform {
  required_version = ">= 0.12"
}

### Backend ###
# S3
###############

# Create S3 Bucket with Versioning enabled

# aws s3api create-bucket --bucket cloudgeeks-terraform --region us-east-1

# aws s3api put-bucket-versioning --bucket cloudgeeks-terraform --versioning-configuration Status=Enabled

####
# S3
####
terraform {
  backend "s3" {
    bucket = "cloudgeeks-terraform"
    key    = "cloudgeeks-terraform.tfstate"
    region = "us-east-1"
  }
}

#####
# S3
#####
module "s3-bucket" {
  source      = "../../../modules/aws-s3"   ###########
  bucket-name = "cloudgeeks-cloudfront"     # Required
  versioning  = "false"                     ###########
}

#############
# CloudFront
#############
resource "aws_cloudfront_distribution" "cloudfront" {

  enabled             = true
  default_root_object = "index.html"
  aliases             = ["cloudfront.cloudgeeks.ca"] # (Required) For HTTPS Requirement, must be DNS Validated & dns name must Only associated be associated with single distribution in single aws account.

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"] # "DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = module.s3-bucket.bucket_name
    viewer_protocol_policy = "redirect-to-https" # redirect-to-https # https-only # allow-all
    compress               = true

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
      
      
      
    forwarded_values {
      query_string = true

      headers = [
        "Origin"
      ]

      cookies {
        forward = "none"
      }
    }
  }

  origin {
    domain_name = module.s3-bucket.bucket_regional_domain_name
    origin_id   = module.s3-bucket.bucket_name

    custom_header {
      name  = "*.invaluable.com"
      value = "*"
    }

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.cloudfront_origin_access_identity.cloudfront_access_identity_path
    }

  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    acm_certificate_arn            = "arn:aws:acm:us-east-1:YOURACCOUNTID:certificate/12345678CBA123456789" # ACM Cert Arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
  }
}

####################################
# Cloudfront Origin Access Identity
####################################
resource "aws_cloudfront_origin_access_identity" "cloudfront_origin_access_identity" {
  comment    = "Only This User is allowed for S3 Read bucket"
  depends_on = [time_sleep.wait_30_seconds]
}

################################
# S3 Bucket Public Access Block
################################
resource "aws_s3_bucket_public_access_block" "s3_bucket_public_access_block" {
  bucket = module.s3-bucket.bucket_name

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  depends_on              = [time_sleep.wait_30_seconds]
}

######################
# IAM Policy Document
######################
data "aws_iam_policy_document" "s3-cloudfront-read_bucket_only" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${module.s3-bucket.bucket_arn}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.cloudfront_origin_access_identity.iam_arn]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [module.s3-bucket.bucket_arn]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.cloudfront_origin_access_identity.iam_arn]
    }
  }
  depends_on = [time_sleep.wait_30_seconds]
}

resource "aws_s3_bucket_policy" "s3_cloudfront_bucket" {
  bucket     = module.s3-bucket.bucket_name
  policy     = data.aws_iam_policy_document.s3-cloudfront-read_bucket_only.json
  depends_on = [time_sleep.wait_60_seconds]
}

resource "null_resource" "previous" {}

resource "time_sleep" "wait_30_seconds" {
  depends_on      = [null_resource.previous]
  create_duration = "30s"
}
resource "time_sleep" "wait_60_seconds" {
  depends_on      = [null_resource.previous]
  create_duration = "60s"
}
