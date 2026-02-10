# -----------------------------------------------------
# Security Group for Monitoring Server
# -----------------------------------------------------

resource "aws_security_group" "monitoring" {
  name        = "${var.project_name}-${var.environment}-sg"
  description = "Security group for monitoring server (Grafana, Prometheus, Loki)"
  vpc_id      = data.aws_vpc.dev.id

  tags = {
    Name = "${var.project_name}-${var.environment}-sg"
  }
}

# -----------------------------------------------------
# Ingress Rules
# -----------------------------------------------------

# SSH
resource "aws_security_group_rule" "ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.allowed_ssh_cidr
  security_group_id = aws_security_group.monitoring.id
  description       = "SSH access"
}

# Grafana (3000) - Public or restricted
resource "aws_security_group_rule" "grafana" {
  type              = "ingress"
  from_port         = 3000
  to_port           = 3000
  protocol          = "tcp"
  cidr_blocks       = var.allowed_grafana_cidr
  security_group_id = aws_security_group.monitoring.id
  description       = "Grafana web UI"
}

# Loki (3100) - From application server only
resource "aws_security_group_rule" "loki_from_app" {
  type              = "ingress"
  from_port         = 3100
  to_port           = 3100
  protocol          = "tcp"
  cidr_blocks       = ["${data.aws_instance.dev_app.private_ip}/32"]
  security_group_id = aws_security_group.monitoring.id
  description       = "Loki from application server"
}

# Prometheus (9090) - Optional public access
resource "aws_security_group_rule" "prometheus_public" {
  count             = var.allow_public_prometheus ? 1 : 0
  type              = "ingress"
  from_port         = 9090
  to_port           = 9090
  protocol          = "tcp"
  cidr_blocks       = var.allowed_grafana_cidr
  security_group_id = aws_security_group.monitoring.id
  description       = "Prometheus web UI (optional)"
}

# Loki (3100) - Optional public access
resource "aws_security_group_rule" "loki_public" {
  count             = var.allow_public_loki ? 1 : 0
  type              = "ingress"
  from_port         = 3100
  to_port           = 3100
  protocol          = "tcp"
  cidr_blocks       = var.allowed_grafana_cidr
  security_group_id = aws_security_group.monitoring.id
  description       = "Loki API (optional)"
}

# Alertmanager (9093) - Optional, for Discord webhooks
resource "aws_security_group_rule" "alertmanager" {
  count             = var.allow_public_prometheus ? 1 : 0
  type              = "ingress"
  from_port         = 9093
  to_port           = 9093
  protocol          = "tcp"
  cidr_blocks       = var.allowed_grafana_cidr
  security_group_id = aws_security_group.monitoring.id
  description       = "Alertmanager (optional)"
}

# -----------------------------------------------------
# Egress Rules
# -----------------------------------------------------

# Allow all outbound traffic
resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.monitoring.id
  description       = "Allow all outbound traffic"
}
