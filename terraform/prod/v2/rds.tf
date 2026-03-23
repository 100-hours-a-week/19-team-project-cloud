# -----------------------------------------------------------------------------
# RDS PostgreSQL
# -----------------------------------------------------------------------------

# 기존 RDS 사용 시: 서브넷 그룹·보안 그룹은 기존 리소스를 참조한다.
data "aws_db_subnet_group" "existing_rds" {
  count = var.use_existing_rds && var.existing_db_subnet_group_name != "" ? 1 : 0
  name  = var.existing_db_subnet_group_name
}

# 보안 그룹은 ID(sg-로 시작)로 지정한다. 이름으로 조회 시 복수 매칭으로 오류가 난다.
data "aws_security_group" "existing_rds" {
  count = var.use_existing_rds && var.existing_rds_security_group_id != "" ? 1 : 0
  id    = var.existing_rds_security_group_id
}

# 신규 배포 시에만 서브넷 그룹 생성
resource "aws_db_subnet_group" "prod_v2" {
  count       = var.use_existing_rds ? 0 : 1
  name        = "${local.name}-db-subnet-group"
  description = "DB subnet group for RDS (refit prod v2)"
  subnet_ids  = local.private_data_subnet_ids

  tags = {
    Name = "${local.name}-db-subnet-group"
  }
}

resource "aws_db_instance" "prod_v2" {
  lifecycle {
    precondition {
      condition     = !var.use_existing_rds || (var.existing_db_subnet_group_name != "" && var.existing_rds_security_group_id != "" && startswith(var.existing_rds_security_group_id, "sg-"))
      error_message = "use_existing_rds=true이면 existing_db_subnet_group_name, existing_rds_security_group_id를 설정해야 한다."
    }
    precondition {
      condition     = (var.ssm_parameter_db_username != "" && var.ssm_parameter_db_password != "") || (var.db_username != "" && var.db_password != "")
      error_message = "RDS 계정: ssm_parameter_db_username·ssm_parameter_db_password 또는 db_username·db_password를 설정해야 한다."
    }
    ignore_changes  = [username, password]
    prevent_destroy = true # 실수로 RDS 삭제 방지 (삭제 시 이 블록 제거 필수)
  }

  identifier     = var.db_instance_identifier
  engine         = "postgres"
  engine_version = var.db_engine_version

  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"

  db_name  = var.db_name
  username = local.db_username
  password = local.db_password
  port     = 5432

  db_subnet_group_name   = var.use_existing_rds ? data.aws_db_subnet_group.existing_rds[0].name : aws_db_subnet_group.prod_v2[0].name
  vpc_security_group_ids = var.use_existing_rds ? [data.aws_security_group.existing_rds[0].id] : [aws_security_group.prod_v2_rds.id]
  multi_az               = false
  publicly_accessible    = false

  backup_retention_period = var.db_backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.db_instance_identifier}-final"
  delete_automated_backups  = false # 삭제 시에도 자동 백업 유지(복구 가능하도록). 기본값 true면 백업까지 삭제됨.

  tags = {
    Name = var.db_instance_identifier
    tier = local.tier_rds
  }
}

# -----------------------------------------------------
# RDS Read Replica (기존 RDS 사용 시에는 미생성)
# -----------------------------------------------------

resource "aws_db_instance" "prod_v2_replica" {
  count                  = var.use_existing_rds ? 0 : 1
  identifier             = "${local.name}-rds-replica"
  replicate_source_db    = aws_db_instance.prod_v2.identifier
  instance_class         = var.db_instance_class
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.prod_v2_rds.id]

  skip_final_snapshot          = true
  backup_retention_period      = 0
  performance_insights_enabled = false

  tags = {
    Name = "${local.name}-rds-replica"
    tier = local.tier_rds_replica
  }
}
