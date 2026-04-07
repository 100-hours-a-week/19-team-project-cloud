# -----------------------------------------------------
# Route53 - DNS Records (refit prod v3 - self-managed K8s)
# Hosted Zone: re-fit.kr (zone ID는 terraform.tfvars에서 주입)
# -----------------------------------------------------

# api-k8s.re-fit.kr → ALB (A alias)
resource "aws_route53_record" "api_k8s" {
  zone_id = var.route53_zone_id
  name    = "api-k8s.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}

# argocd.re-fit.kr → ALB (CNAME)
resource "aws_route53_record" "argocd" {
  zone_id = var.route53_zone_id
  name    = "argocd.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [aws_lb.app.dns_name]
}

# monitoring.re-fit.kr → ALB (A alias)
resource "aws_route53_record" "monitoring" {
  zone_id = var.route53_zone_id
  name    = "monitoring.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}
