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

# -----------------------------------------------------
# Frontend ASG SG (Next.js, port 3000)
# -----------------------------------------------------

resource "aws_security_group" "prod_v2_frontend" {
  name        = "${local.name}-frontend-sg"
  description = "Security group for Frontend ASG Next.js (refit prod v2)"
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

resource "aws_vpc_security_group_egress_rule" "prod_v2_frontend_all" {
  security_group_id = aws_security_group.prod_v2_frontend.id
  description       = "All outbound (Internal ALB, internet for npm etc)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# -----------------------------------------------------
# Internal ALB SG (VPC internal)
# -----------------------------------------------------

resource "aws_security_group" "prod_v2_alb_internal" {
  name        = "${local.name}-alb-internal-sg"
  description = "Security group for Internal ALB (refit prod v2)"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${local.name}-alb-internal-sg"
    tier = local.tier_alb_int
  }
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_alb_internal_http" {
  security_group_id = aws_security_group.prod_v2_alb_internal.id
  description       = "HTTP from VPC"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "prod_v2_alb_internal_backend" {
  security_group_id            = aws_security_group.prod_v2_alb_internal.id
  description                  = "To Backend"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.prod_v2_backend.id
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_alb_internal_frontend" {
  security_group_id            = aws_security_group.prod_v2_alb_internal.id
  description                  = "HTTP from Frontend SSR to Backend"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.prod_v2_frontend.id
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

resource "aws_vpc_security_group_ingress_rule" "prod_v2_backend_8080_internal_alb" {
  security_group_id            = aws_security_group.prod_v2_backend.id
  description                  = "Backend from Internal ALB"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.prod_v2_alb_internal.id
}

resource "aws_vpc_security_group_egress_rule" "prod_v2_backend_all" {
  security_group_id = aws_security_group.prod_v2_backend.id
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
# Kafka SG (설계도: Kafka 별도 EC2 3대, ASG 없음)
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

resource "aws_vpc_security_group_egress_rule" "prod_v2_kafka_all" {
  security_group_id = aws_security_group.prod_v2_kafka.id
  description       = "All outbound"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

