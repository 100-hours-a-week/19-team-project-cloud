# -----------------------------------------------------------------------------
# CloudFront (설계도: Route 53 → WAF → CloudFront → ALB)
# 오리진 = External ALB. 뷰어 인증서는 us-east-1 ACM 필요.
# -----------------------------------------------------------------------------

locals {
  cloudfront_origin_domain = var.cloudfront_origin_domain != "" ? var.cloudfront_origin_domain : aws_lb.prod_v2_external.dns_name
  cloudfront_origin_https  = var.cloudfront_origin_domain != ""
}

resource "aws_cloudfront_distribution" "prod_v2" {
  count        = var.cloudfront_enabled ? 1 : 0
  enabled      = true
  comment      = "${local.name} - WAF + ALB origin"
  aliases      = var.cloudfront_aliases
  price_class  = "PriceClass_100" # North America, Europe만 (최저 비용)

  origin {
    domain_name = local.cloudfront_origin_domain
    origin_id   = "alb-${local.name}"

    custom_header {
      name  = "X-Forwarded-Proto"
      value = "https"
    }

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = local.cloudfront_origin_https ? "https-only" : "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "alb-${local.name}"
    viewer_protocol_policy  = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    compress               = true

    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled (API/동적 콘텐츠)
  }

  # 뷰어 인증서: 커스텀 도메인 사용 시 us-east-1 ACM 필요
  viewer_certificate {
    cloudfront_default_certificate = local.cloudfront_acm_arn == ""
    acm_certificate_arn            = local.cloudfront_acm_arn != "" ? local.cloudfront_acm_arn : null
    ssl_support_method             = local.cloudfront_acm_arn != "" ? "sni-only" : null
    minimum_protocol_version       = local.cloudfront_acm_arn != "" ? "TLSv1.2_2021" : null
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  web_acl_id = aws_wafv2_web_acl.prod_v2[0].arn

  tags = {
    Name = "${local.name}-cloudfront"
  }
}
