# -----------------------------------------------------------------------------
# WAF v2 (설계도: Route 53 → WAF → CloudFront → ALB)
# CloudFront에 붙이는 Web ACL은 반드시 us-east-1에 생성
# cloudfront_enabled=true일 때만 생성
# -----------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "prod_v2" {
  count       = var.cloudfront_enabled ? 1 : 0
  provider    = aws.us_east_1
  name        = "${local.name}-waf"
  description = "WAF for prod v2 CloudFront (Route53 → WAF → CloudFront → ALB)"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # AWS 관리 규칙: 일반 취약점 (SQLi, XSS 등)
  dynamic "rule" {
    for_each = var.waf_enable_managed_rules ? [1] : []
    content {
      name     = "AWS-AWSManagedRulesCommonRuleSet"
      priority = 1
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesCommonRuleSet"
        }
      }
    }
  }

  # AWS 관리 규칙: 알려진 악성 입력
  dynamic "rule" {
    for_each = var.waf_enable_managed_rules ? [1] : []
    content {
      name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
      priority = 2
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesKnownBadInputsRuleSet"
        }
      }
    }
  }

  # IP 기반 rate limiting (분당 요청 수 제한)
  dynamic "rule" {
    for_each = var.waf_rate_limit > 0 ? [1] : []
    content {
      name     = "RateLimitRule"
      priority = 10
      action {
        block {}
      }
      statement {
        rate_based_statement {
          limit              = var.waf_rate_limit
          aggregate_key_type = "IP"
        }
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${replace(local.name, "-", "_")}_waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${local.name}-waf"
  }
}
