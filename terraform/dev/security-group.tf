# -----------------------------------------------------
# Security Group
# -----------------------------------------------------
resource "aws_security_group" "main" {
  name        = "${var.project_name}-${var.environment}-sg"
  description = "Security group for ${var.project_name} ${var.environment} server"
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

# -----------------------------------------------------
# Monitoring - Metrics Collection
# -----------------------------------------------------

# Node Exporter (9100) - System metrics
resource "aws_vpc_security_group_ingress_rule" "node_exporter" {
  security_group_id = aws_security_group.main.id
  description       = "Node Exporter metrics from monitoring server"
  ip_protocol       = "tcp"
  from_port         = 9100
  to_port           = 9100
  cidr_ipv4         = "10.1.2.163/32" # Monitoring server private IP

  tags = {
    Name = "node-exporter"
  }
}

# cAdvisor (8081) - Container metrics
resource "aws_vpc_security_group_ingress_rule" "cadvisor" {
  security_group_id = aws_security_group.main.id
  description       = "cAdvisor metrics from monitoring server"
  ip_protocol       = "tcp"
  from_port         = 8081
  to_port           = 8081
  cidr_ipv4         = "10.1.2.163/32" # Monitoring server private IP

  tags = {
    Name = "cadvisor"
  }
}

# Postgres Exporter (9187) - Database metrics
resource "aws_vpc_security_group_ingress_rule" "postgres_exporter" {
  security_group_id = aws_security_group.main.id
  description       = "Postgres Exporter metrics from monitoring server"
  ip_protocol       = "tcp"
  from_port         = 9187
  to_port           = 9187
  cidr_ipv4         = "10.1.2.163/32" # Monitoring server private IP

  tags = {
    Name = "postgres-exporter"
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
