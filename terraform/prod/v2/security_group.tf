# -----------------------------------------------------
# Security Groups (refit-prod-v2)
# -----------------------------------------------------

# -----------------------------------------------------
# External ALB SG (internet-facing)
# -----------------------------------------------------

resource "aws_security_group" "prod_v2_alb_external" {
  name        = "${local.name}-alb-external-sg"
  description = "Security group for External ALB (refit prod v2)"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${local.name}-alb-external-sg"
    tier = local.tier_alb_ext
  }
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_alb_external_http" {
  security_group_id = aws_security_group.prod_v2_alb_external.id
  description       = "HTTP"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_alb_external_https" {
  security_group_id = aws_security_group.prod_v2_alb_external.id
  description       = "HTTPS"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "prod_v2_alb_external_frontend" {
  security_group_id            = aws_security_group.prod_v2_alb_external.id
  description                  = "To Frontend (Next.js)"
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = aws_security_group.prod_v2_frontend.id
}

resource "aws_vpc_security_group_egress_rule" "prod_v2_alb_external_backend" {
  security_group_id            = aws_security_group.prod_v2_alb_external.id
  description                  = "To Backend"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.prod_v2_backend.id
}

resource "aws_vpc_security_group_egress_rule" "prod_v2_alb_external_ai" {
  security_group_id            = aws_security_group.prod_v2_alb_external.id
  description                  = "To AI (port 8000)"
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  referenced_security_group_id = aws_security_group.prod_v2_ai.id
}

resource "aws_vpc_security_group_egress_rule" "prod_v2_alb_external_monitoring" {
  security_group_id            = aws_security_group.prod_v2_alb_external.id
  description                  = "To Monitoring Grafana (port 3000)"
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = aws_security_group.prod_v2_monitoring.id
}

resource "aws_vpc_security_group_egress_rule" "prod_v2_alb_external_k8s_nodeport" {
  security_group_id = aws_security_group.prod_v2_alb_external.id
  description       = "To K8s NodePort via VPC peering"
  ip_protocol       = "tcp"
  from_port         = 32678
  to_port           = 32678
  cidr_ipv4         = var.k8s_vpc_cidr
}

# -----------------------------------------------------
# Frontend SG (Next.js, port 3000) - kept for CodeDeploy
# -----------------------------------------------------

resource "aws_security_group" "prod_v2_frontend" {
  name        = "${local.name}-frontend-sg"
  description = "Security group for Frontend (refit prod v2, used for CodeDeploy)"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${local.name}-frontend-sg"
    tier = local.tier_frontend
  }
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_frontend_3000_external_alb" {
  security_group_id            = aws_security_group.prod_v2_frontend.id
  description                  = "Next.js from External ALB"
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = aws_security_group.prod_v2_alb_external.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_frontend_ssh_self" {
  security_group_id            = aws_security_group.prod_v2_frontend.id
  description                  = "SSH from Frontend (same SG)"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.prod_v2_frontend.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_frontend_ssh_bastion" {
  count = var.existing_bastion_security_group_id != "" ? 1 : 0

  security_group_id            = aws_security_group.prod_v2_frontend.id
  description                  = "SSH from Bastion (refit jump host)"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = var.existing_bastion_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "prod_v2_frontend_all" {
  security_group_id = aws_security_group.prod_v2_frontend.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# -----------------------------------------------------
# Backend ASG SG
# -----------------------------------------------------

resource "aws_security_group" "prod_v2_backend" {
  name        = "${local.name}-backend-sg"
  description = "Security group for Backend ASG (refit prod v2)"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${local.name}-backend-sg"
    tier = local.tier_backend
  }
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_backend_8080_external_alb" {
  security_group_id            = aws_security_group.prod_v2_backend.id
  description                  = "Backend from External ALB"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.prod_v2_alb_external.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_backend_ssh_bastion" {
  count = var.existing_bastion_security_group_id != "" ? 1 : 0

  security_group_id            = aws_security_group.prod_v2_backend.id
  description                  = "SSH from Bastion (refit jump host)"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = var.existing_bastion_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "prod_v2_backend_all" {
  security_group_id = aws_security_group.prod_v2_backend.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# -----------------------------------------------------
# AI EC2 SG
# -----------------------------------------------------

resource "aws_security_group" "prod_v2_ai" {
  name        = "${local.name}-ai-sg"
  description = "Security group for AI EC2 (refit prod v2)"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${local.name}-ai-sg"
    tier = local.tier_ai
  }
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_ai_8000_external_alb" {
  security_group_id            = aws_security_group.prod_v2_ai.id
  description                  = "AI from External ALB"
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  referenced_security_group_id = aws_security_group.prod_v2_alb_external.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_ai_8000_monitoring" {
  security_group_id            = aws_security_group.prod_v2_ai.id
  description                  = "AI from Monitoring"
  ip_protocol                  = "tcp"
  from_port                    = 8000
  to_port                      = 8000
  referenced_security_group_id = aws_security_group.prod_v2_monitoring.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_ai_ssh" {
  security_group_id = aws_security_group.prod_v2_ai.id
  description       = "SSH"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_ai_9100_monitoring" {
  security_group_id            = aws_security_group.prod_v2_ai.id
  description                  = "Node Exporter from Monitoring"
  ip_protocol                  = "tcp"
  from_port                    = 9100
  to_port                      = 9100
  referenced_security_group_id = aws_security_group.prod_v2_monitoring.id
}

resource "aws_vpc_security_group_egress_rule" "prod_v2_ai_all" {
  security_group_id = aws_security_group.prod_v2_ai.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# -----------------------------------------------------
# Monitoring EC2 SG
# -----------------------------------------------------

resource "aws_security_group" "prod_v2_monitoring" {
  name        = "refit-v2-monitoring-sg"
  description = "Security group for Monitoring EC2 (refit prod v2)"
  vpc_id      = local.vpc_id

  tags = {
    Name = "refit-v2-monitoring-sg"
    tier = local.tier_monitoring
  }
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_monitoring_3000_external_alb" {
  security_group_id            = aws_security_group.prod_v2_monitoring.id
  description                  = "Grafana from External ALB"
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = aws_security_group.prod_v2_alb_external.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_monitoring_4317_backend" {
  security_group_id            = aws_security_group.prod_v2_monitoring.id
  description                  = "OTLP gRPC from Backend"
  ip_protocol                  = "tcp"
  from_port                    = 4317
  to_port                      = 4317
  referenced_security_group_id = aws_security_group.prod_v2_backend.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_monitoring_4317_frontend" {
  security_group_id            = aws_security_group.prod_v2_monitoring.id
  description                  = "OTLP gRPC from Frontend"
  ip_protocol                  = "tcp"
  from_port                    = 4317
  to_port                      = 4317
  referenced_security_group_id = aws_security_group.prod_v2_frontend.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_monitoring_4317_ai" {
  security_group_id            = aws_security_group.prod_v2_monitoring.id
  description                  = "OTLP gRPC from AI"
  ip_protocol                  = "tcp"
  from_port                    = 4317
  to_port                      = 4317
  referenced_security_group_id = aws_security_group.prod_v2_ai.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_monitoring_4318_backend" {
  security_group_id            = aws_security_group.prod_v2_monitoring.id
  description                  = "OTLP HTTP from Backend"
  ip_protocol                  = "tcp"
  from_port                    = 4318
  to_port                      = 4318
  referenced_security_group_id = aws_security_group.prod_v2_backend.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_monitoring_4318_frontend" {
  security_group_id            = aws_security_group.prod_v2_monitoring.id
  description                  = "OTLP HTTP from Frontend"
  ip_protocol                  = "tcp"
  from_port                    = 4318
  to_port                      = 4318
  referenced_security_group_id = aws_security_group.prod_v2_frontend.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_monitoring_4318_ai" {
  security_group_id            = aws_security_group.prod_v2_monitoring.id
  description                  = "OTLP HTTP from AI"
  ip_protocol                  = "tcp"
  from_port                    = 4318
  to_port                      = 4318
  referenced_security_group_id = aws_security_group.prod_v2_ai.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_monitoring_9091_external_alb" {
  security_group_id            = aws_security_group.prod_v2_monitoring.id
  description                  = "k6 Prometheus remote-write from External ALB"
  ip_protocol                  = "tcp"
  from_port                    = 9091
  to_port                      = 9091
  referenced_security_group_id = aws_security_group.prod_v2_alb_external.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_monitoring_9091_backend" {
  security_group_id            = aws_security_group.prod_v2_monitoring.id
  description                  = "k6 remote-write from Backend"
  ip_protocol                  = "tcp"
  from_port                    = 9091
  to_port                      = 9091
  referenced_security_group_id = aws_security_group.prod_v2_backend.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_monitoring_9125_backend" {
  security_group_id            = aws_security_group.prod_v2_monitoring.id
  description                  = "k6 StatsD UDP from Backend"
  ip_protocol                  = "udp"
  from_port                    = 9125
  to_port                      = 9125
  referenced_security_group_id = aws_security_group.prod_v2_backend.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_monitoring_3100_external_alb" {
  security_group_id            = aws_security_group.prod_v2_monitoring.id
  description                  = "Loki from External ALB"
  ip_protocol                  = "tcp"
  from_port                    = 3100
  to_port                      = 3100
  referenced_security_group_id = aws_security_group.prod_v2_alb_external.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_monitoring_3100_ai" {
  security_group_id            = aws_security_group.prod_v2_monitoring.id
  description                  = "Loki from AI"
  ip_protocol                  = "tcp"
  from_port                    = 3100
  to_port                      = 3100
  referenced_security_group_id = aws_security_group.prod_v2_ai.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_monitoring_ssh" {
  security_group_id = aws_security_group.prod_v2_monitoring.id
  description       = "SSH"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "prod_v2_monitoring_all" {
  security_group_id = aws_security_group.prod_v2_monitoring.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# -----------------------------------------------------
# RDS SG
# -----------------------------------------------------

resource "aws_security_group" "prod_v2_rds" {
  name        = "${local.name}-rds-sg"
  description = "Security group for RDS (refit prod v2)"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${local.name}-rds-sg"
    tier = local.tier_rds
  }
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_rds_5432" {
  security_group_id            = aws_security_group.prod_v2_rds.id
  description                  = "PostgreSQL from Backend"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.prod_v2_backend.id
}

# -----------------------------------------------------
# ElastiCache SG
# -----------------------------------------------------

resource "aws_security_group" "prod_v2_elasticache" {
  name        = "${local.name}-elasticache-sg"
  description = "Security group for ElastiCache Valkey (refit prod v2)"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${local.name}-elasticache-sg"
    tier = local.tier_elasticache
  }
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_elasticache_6379" {
  security_group_id            = aws_security_group.prod_v2_elasticache.id
  description                  = "Redis from Backend"
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.prod_v2_backend.id
}

# -----------------------------------------------------
# Kafka SG (단일 EC2, ASG 없음)
# -----------------------------------------------------

resource "aws_security_group" "prod_v2_kafka" {
  name        = "${local.name}-kafka-sg"
  description = "Security group for Kafka EC2 (refit prod v2, separate from Backend)"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${local.name}-kafka-sg"
    tier = local.tier_kafka
  }
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_kafka_9092_backend" {
  security_group_id            = aws_security_group.prod_v2_kafka.id
  description                  = "Kafka from Backend"
  ip_protocol                  = "tcp"
  from_port                    = 9092
  to_port                      = 9092
  referenced_security_group_id = aws_security_group.prod_v2_backend.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_kafka_9092_self" {
  security_group_id            = aws_security_group.prod_v2_kafka.id
  description                  = "Kafka cluster (broker to broker)"
  ip_protocol                  = "tcp"
  from_port                    = 9092
  to_port                      = 9092
  referenced_security_group_id = aws_security_group.prod_v2_kafka.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_kafka_9093_self" {
  security_group_id            = aws_security_group.prod_v2_kafka.id
  description                  = "Kafka KRaft controller (node 간 통신)"
  ip_protocol                  = "tcp"
  from_port                    = 9093
  to_port                      = 9093
  referenced_security_group_id = aws_security_group.prod_v2_kafka.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_kafka_9999_monitoring" {
  security_group_id = aws_security_group.prod_v2_kafka.id
  description       = "JMX (모니터링 EC2 → Kafka)"
  ip_protocol       = "tcp"
  from_port         = 9999
  to_port           = 9999
  cidr_ipv4         = local.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "prod_v2_kafka_all" {
  security_group_id = aws_security_group.prod_v2_kafka.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
