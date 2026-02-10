# -----------------------------------------------------
# ALB - External (Public) + Internal (refit-prod-v2)
# Listener rules from Caddyfile
# -----------------------------------------------------

# -----------------------------------------------------
# Target Groups
# -----------------------------------------------------

resource "aws_lb_target_group" "prod_v2_backend" {
  name     = "${local.name}-backend-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.prod_v2.id

  health_check {
    enabled             = true
    path                = "/actuator/health"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  tags = {
    Name = "${local.name}-backend-tg"
    tier = local.tier_backend
  }
}

resource "aws_lb_target_group" "prod_v2_frontend" {
  name     = "${local.name}-frontend-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.prod_v2.id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30

  tags = {
    Name = "${local.name}-frontend-tg"
    tier = local.tier_frontend
  }
}

# -----------------------------------------------------
# External ALB (internet-facing)
# -----------------------------------------------------

resource "aws_lb" "prod_v2_external" {
  name               = "${local.name}-external-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.prod_v2_alb_external.id]
  subnets            = aws_subnet.prod_v2_public[*].id

  tags = {
    Name = "${local.name}-external-alb"
    tier = local.tier_alb_ext
  }
}

resource "aws_lb_listener" "prod_v2_external_https" {
  lifecycle {
    precondition {
      condition     = var.ssm_parameter_acm_certificate_arn != "" || var.acm_certificate_arn != ""
      error_message = "ACM 인증서: ssm_parameter_acm_certificate_arn 또는 acm_certificate_arn을 설정해야 한다."
    }
  }

  load_balancer_arn = aws_lb.prod_v2_external.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = local.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_frontend.arn
  }
}

# API/Backend path rules (order = priority) - 나머지는 Backend로
resource "aws_lb_listener_rule" "prod_v2_external_api_ai" {
  listener_arn = aws_lb_listener.prod_v2_external_https.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/ai/*"]
    }
  }
}

resource "aws_lb_listener_rule" "prod_v2_external_ai" {
  listener_arn = aws_lb_listener.prod_v2_external_https.arn
  priority     = 2

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/ai/*"]
    }
  }
}

resource "aws_lb_listener_rule" "prod_v2_external_swagger" {
  listener_arn = aws_lb_listener.prod_v2_external_https.arn
  priority     = 3

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/swagger-ui/*"]
    }
  }
}

resource "aws_lb_listener_rule" "prod_v2_external_v3_docs" {
  listener_arn = aws_lb_listener.prod_v2_external_https.arn
  priority     = 4

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/v3/api-docs*"]
    }
  }
}

resource "aws_lb_listener_rule" "prod_v2_external_actuator" {
  listener_arn = aws_lb_listener.prod_v2_external_https.arn
  priority     = 5

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/actuator/*"]
    }
  }
}

resource "aws_lb_listener_rule" "prod_v2_external_ws" {
  listener_arn = aws_lb_listener.prod_v2_external_https.arn
  priority     = 6

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/ws*"]
    }
  }
}

resource "aws_lb_listener_rule" "prod_v2_external_api_ws" {
  listener_arn = aws_lb_listener.prod_v2_external_https.arn
  priority     = 7

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/ws*"]
    }
  }
}

resource "aws_lb_listener_rule" "prod_v2_external_api" {
  listener_arn = aws_lb_listener.prod_v2_external_https.arn
  priority     = 8

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

resource "aws_lb_listener_rule" "prod_v2_external_dev" {
  listener_arn = aws_lb_listener.prod_v2_external_https.arn
  priority     = 9

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/dev/*"]
    }
  }
}

# Default already forwards to Backend (1차). When Frontend ASG exists, change default to Frontend TG.

resource "aws_lb_listener" "prod_v2_external_http" {
  load_balancer_arn = aws_lb.prod_v2_external.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# CloudFront 오리진이 ALB 80 포트 사용 시: CloudFront 요청만 포워드(리다이렉트 제외)
resource "aws_lb_listener_rule" "prod_v2_external_http_cloudfront_backend" {
  count        = var.cloudfront_enabled ? 1 : 0
  listener_arn = aws_lb_listener.prod_v2_external_http.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    http_header {
      http_header_name = "x-forwarded-proto"
      values           = ["https"]
    }
  }
  condition {
    path_pattern {
      values = ["/api/ai/*", "/ai/*", "/swagger-ui/*", "/v3/api-docs*", "/actuator/*", "/ws*", "/api/ws*", "/api/*", "/dev/*"]
    }
  }
}

resource "aws_lb_listener_rule" "prod_v2_external_http_cloudfront_frontend" {
  count        = var.cloudfront_enabled ? 1 : 0
  listener_arn = aws_lb_listener.prod_v2_external_http.arn
  priority     = 2

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_frontend.arn
  }

  condition {
    http_header {
      http_header_name = "x-forwarded-proto"
      values           = ["https"]
    }
  }
}

# -----------------------------------------------------
# Internal ALB (VPC internal, Frontend -> Backend)
# -----------------------------------------------------

resource "aws_lb" "prod_v2_internal" {
  name               = "${local.name}-internal-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.prod_v2_alb_internal.id]
  subnets            = aws_subnet.prod_v2_private_backend[*].id

  tags = {
    Name = "${local.name}-internal-alb"
    tier = local.tier_alb_int
  }
}

resource "aws_lb_listener" "prod_v2_internal_http" {
  load_balancer_arn = aws_lb.prod_v2_internal.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }
}

# Internal ALB path rules (same as Caddyfile, all to Backend)
resource "aws_lb_listener_rule" "prod_v2_internal_api_ai" {
  listener_arn = aws_lb_listener.prod_v2_internal_http.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/ai/*"]
    }
  }
}

resource "aws_lb_listener_rule" "prod_v2_internal_ai" {
  listener_arn = aws_lb_listener.prod_v2_internal_http.arn
  priority     = 2

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/ai/*"]
    }
  }
}

resource "aws_lb_listener_rule" "prod_v2_internal_swagger" {
  listener_arn = aws_lb_listener.prod_v2_internal_http.arn
  priority     = 3

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/swagger-ui/*"]
    }
  }
}

resource "aws_lb_listener_rule" "prod_v2_internal_v3_docs" {
  listener_arn = aws_lb_listener.prod_v2_internal_http.arn
  priority     = 4

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/v3/api-docs*"]
    }
  }
}

resource "aws_lb_listener_rule" "prod_v2_internal_actuator" {
  listener_arn = aws_lb_listener.prod_v2_internal_http.arn
  priority     = 5

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/actuator/*"]
    }
  }
}

resource "aws_lb_listener_rule" "prod_v2_internal_ws" {
  listener_arn = aws_lb_listener.prod_v2_internal_http.arn
  priority     = 6

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/ws*"]
    }
  }
}

resource "aws_lb_listener_rule" "prod_v2_internal_api_ws" {
  listener_arn = aws_lb_listener.prod_v2_internal_http.arn
  priority     = 7

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/ws*"]
    }
  }
}

resource "aws_lb_listener_rule" "prod_v2_internal_api" {
  listener_arn = aws_lb_listener.prod_v2_internal_http.arn
  priority     = 8

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

resource "aws_lb_listener_rule" "prod_v2_internal_dev" {
  listener_arn = aws_lb_listener.prod_v2_internal_http.arn
  priority     = 9

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_v2_backend.arn
  }

  condition {
    path_pattern {
      values = ["/dev/*"]
    }
  }
}
