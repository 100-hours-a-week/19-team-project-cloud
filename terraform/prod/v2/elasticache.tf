# -----------------------------------------------------
# ElastiCache Valkey / Redis (refit-prod-v2)
# -----------------------------------------------------

resource "aws_elasticache_subnet_group" "prod_v2" {
  name        = "${local.name}-elasticache-subnet-group"
  description = "Subnet group for ElastiCache (refit prod v2)"
  subnet_ids  = local.private_data_subnet_ids
}

resource "aws_elasticache_replication_group" "prod_v2" {
  replication_group_id = "refit-redis"
  description          = "ElastiCache Valkey for refit prod v2"

  engine               = "valkey"
  engine_version       = "8.0"
  node_type          = var.elasticache_node_type
  num_cache_clusters = var.elasticache_num_cache_clusters
  port               = 6379

  subnet_group_name  = aws_elasticache_subnet_group.prod_v2.name
  security_group_ids = [aws_security_group.prod_v2_elasticache.id]

  at_rest_encryption_enabled = false
  transit_encryption_enabled  = false

  lifecycle {
    # AUTH 수정은 transit_encryption 켜진 경우만 가능. 기존 클러스터 보호
    ignore_changes = [auth_token]
  }

  tags = {
    Name = "${local.name}-elasticache"
    tier = local.tier_elasticache
  }
}
