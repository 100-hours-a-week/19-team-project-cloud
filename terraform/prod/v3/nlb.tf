# -----------------------------------------------------
# NLB - Control Plane (refit prod v3 - self-managed K8s)
# Master 3대의 K8s API server(6443)를 HA로 노출
# Cilium이 k8sServiceHost로 이 NLB DNS를 사용
# -----------------------------------------------------

resource "aws_lb" "cp" {
  name               = "${local.prefix}-cp-nlb"
  internal           = false
  load_balancer_type = "network"

  subnets = [
    aws_subnet.pub_a.id,
    aws_subnet.pub_b.id,
    aws_subnet.pub_c.id,
  ]

  enable_deletion_protection = false

  tags = { Name = "${local.prefix}-cp-nlb" }
}

# ------- Target Group (IP type → master private IPs) -------
resource "aws_lb_target_group" "cp" {
  name        = "${local.prefix}-cp-tg"
  port        = 6443
  protocol    = "TCP"
  vpc_id      = aws_vpc.k8s.id
  target_type = "ip"

  health_check {
    protocol            = "TCP"
    port                = "6443"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = { Name = "${local.prefix}-cp-tg" }
}

# Master private IP 등록
resource "aws_lb_target_group_attachment" "cp" {
  for_each = local.master_nodes

  target_group_arn  = aws_lb_target_group.cp.arn
  target_id         = each.value.private_ip
  port              = 6443
  availability_zone = each.value.az
}

# ------- Listener: TCP 6443 -------
resource "aws_lb_listener" "cp_6443" {
  load_balancer_arn = aws_lb.cp.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cp.arn
  }
}
