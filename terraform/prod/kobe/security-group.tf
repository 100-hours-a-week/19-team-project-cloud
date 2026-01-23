# -----------------------------------------------------
# Security Group
# -----------------------------------------------------
resource "aws_security_group" "main" {
  name        = "${var.project_name}-${var.environment}-sg"
  description = "Security group for Re-Fit ${var.environment} server"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-sg"
  }
}

# -----------------------------------------------------
# Ingress Rules
# -----------------------------------------------------

# SSH (22)
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.main.id
  description       = "SSH access"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.allowed_ssh_cidr[0]

  tags = {
    Name = "ssh"
  }
}

# HTTP (80)
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.main.id
  description       = "HTTP access"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "http"
  }
}

# HTTPS (443)
resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.main.id
  description       = "HTTPS access"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "https"
  }
}

# PostgreSQL (5432) - 조건부 생성
resource "aws_vpc_security_group_ingress_rule" "postgresql" {
  count = length(var.allowed_db_cidr) > 0 ? 1 : 0

  security_group_id = aws_security_group.main.id
  description       = "PostgreSQL access"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "postgresql"
  }
}

# -----------------------------------------------------
# Egress Rules
# -----------------------------------------------------

# All outbound traffic
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.main.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "all-outbound"
  }
}
