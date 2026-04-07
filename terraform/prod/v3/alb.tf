# -----------------------------------------------------
# ALB - App Traffic (refit prod v3 - self-managed K8s)
# Worker 3대의 NodePort(30080)로 앱 트래픽 분산
# Cilium Gateway API NodePort를 통해 내부 라우팅
# -----------------------------------------------------

# ACM 인증서 (기존 발급된 것을 data source로 참조)
data "aws_acm_certificate" "k8s" {
  domain   = "api-k8s.${var.domain_name}"
  statuses = ["ISSUED"]
}

# ------- ALB -------
resource "aws_lb" "app" {
  name               = "${local.prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]

  # 실제 환경: ap-northeast-2a, ap-northeast-2c (2개 서브넷)
  subnets = [
    aws_subnet.pub_a.id,
    aws_subnet.pub_c.id,
  ]

  enable_deletion_protection = false

  tags = { Name = "${local.prefix}-alb" }
}

# ------- Target Group (instance type → worker NodePort) -------
resource "aws_lb_target_group" "app" {
  name        = "${local.prefix}-tg"
  port        = var.alb_target_port # 32678 (Cilium Gateway NodePort)
  protocol    = "HTTP"
  vpc_id      = aws_vpc.k8s.id
  target_type = "instance"

  health_check {
    protocol            = "HTTP"
    port                = tostring(var.alb_nodeport) # 30080
    path                = "/actuator/health"
    matcher             = "200,404"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
  }

  tags = { Name = "${local.prefix}-tg" }
}

# Worker 인스턴스 등록 (포트 30080 - health check용, 실제 트래픽은 32678)
resource "aws_lb_target_group_attachment" "app_worker" {
  for_each = aws_instance.worker

  target_group_arn = aws_lb_target_group.app.arn
  target_id        = each.value.id
  port             = var.alb_nodeport # 30080
}

# ------- Listener: HTTP 80 → HTTPS redirect -------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
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

# HTTP 80: monitoring.re-fit.kr → redirect (동일 redirect)
resource "aws_lb_listener_rule" "http_monitoring_redirect" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  condition {
    host_header {
      values = ["monitoring.${var.domain_name}"]
    }
  }

  action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ------- Listener: HTTPS 443 -------
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.k8s.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# HTTPS 443: monitoring.re-fit.kr → 동일 TG (Cilium이 내부 라우팅)
resource "aws_lb_listener_rule" "https_monitoring" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  condition {
    host_header {
      values = ["monitoring.${var.domain_name}"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
