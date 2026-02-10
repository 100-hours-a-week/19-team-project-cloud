# -----------------------------------------------------------------------------
# RDS Proxy (Connection Pooling)
# Backend → RDS Proxy → RDS
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "prod_v2_rds" {
  count       = var.rds_proxy_enabled ? 1 : 0
  name        = "${replace(local.name, ".", "-")}/rds-credentials"
  description = "RDS credentials for RDS Proxy"

  tags = {
    Name = "${local.name}-rds-secret"
    tier = local.tier_rds
  }
}

resource "aws_secretsmanager_secret_version" "prod_v2_rds" {
  count     = var.rds_proxy_enabled ? 1 : 0
  secret_id = aws_secretsmanager_secret.prod_v2_rds[0].id

  secret_string = jsonencode({
    username = local.db_username
    password = local.db_password
  })
}

resource "aws_iam_role" "prod_v2_rds_proxy" {
  count = var.rds_proxy_enabled ? 1 : 0

  name = "${var.name_prefix}-rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-rds-proxy-role"
  }
}

resource "aws_iam_role_policy" "prod_v2_rds_proxy_secrets" {
  count = var.rds_proxy_enabled ? 1 : 0

  name   = "${var.name_prefix}-rds-proxy-secrets"
  role   = aws_iam_role.prod_v2_rds_proxy[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.prod_v2_rds[0].arn
      }
    ]
  })
}

resource "aws_security_group" "prod_v2_rds_proxy" {
  count       = var.rds_proxy_enabled ? 1 : 0
  name        = "${local.name}-rds-proxy-sg"
  description = "Security group for RDS Proxy"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${local.name}-rds-proxy-sg"
    tier = local.tier_rds
  }
}

resource "aws_vpc_security_group_ingress_rule" "prod_v2_rds_proxy_5432" {
  count = var.rds_proxy_enabled ? 1 : 0

  security_group_id            = aws_security_group.prod_v2_rds_proxy[0].id
  description                  = "PostgreSQL from Backend"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.prod_v2_backend.id
}

# RDS SG: Proxy에서 RDS로 연결 허용
resource "aws_vpc_security_group_ingress_rule" "prod_v2_rds_from_proxy" {
  count = var.rds_proxy_enabled ? 1 : 0

  security_group_id            = var.use_existing_rds ? data.aws_security_group.existing_rds[0].id : aws_security_group.prod_v2_rds.id
  description                  = "PostgreSQL from RDS Proxy"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.prod_v2_rds_proxy[0].id
}

resource "aws_db_proxy" "prod_v2" {
  count = var.rds_proxy_enabled ? 1 : 0

  name                   = "${replace(local.name, ".", "-")}-proxy"
  engine_family          = "POSTGRESQL"
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.prod_v2_rds_proxy[0].arn
  vpc_security_group_ids = [aws_security_group.prod_v2_rds_proxy[0].id]
  vpc_subnet_ids         = var.use_existing_rds ? data.aws_db_subnet_group.existing_rds[0].subnet_ids : local.private_data_subnet_ids

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.prod_v2_rds[0].arn
  }

  tags = {
    Name = "${local.name}-rds-proxy"
    tier = local.tier_rds
  }
}

resource "aws_db_proxy_default_target_group" "prod_v2" {
  count = var.rds_proxy_enabled ? 1 : 0

  db_proxy_name = aws_db_proxy.prod_v2[0].name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent     = 100
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "prod_v2" {
  count = var.rds_proxy_enabled ? 1 : 0

  db_proxy_name          = aws_db_proxy.prod_v2[0].name
  target_group_name     = aws_db_proxy_default_target_group.prod_v2[0].name
  db_instance_identifier = aws_db_instance.prod_v2.identifier
}
