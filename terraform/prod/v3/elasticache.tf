# -----------------------------------------------------
# ElastiCache - Valkey (Redis-compatible)
# refit prod v3 - self-managed K8s
# Valkey 8.0.1, cache.t4g.micro, 1 node (ap-northeast-2c)
# No encryption, no auth (VPC SG 기반 보안)
# -----------------------------------------------------

# ------- Subnet Group -------
resource "aws_elasticache_subnet_group" "k8s" {
  name       = "${local.prefix}-subnet-group"
  subnet_ids = [aws_subnet.pub_a.id, aws_subnet.pub_c.id]

  tags = { Name = "${local.prefix}-subnet-group" }
}

# ------- Replication Group (single-node) -------
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "refit-redis"
  description          = "Refit Valkey cache for K8s workloads"

  engine               = "valkey"
  engine_version       = var.elasticache_engine_version
  node_type            = var.elasticache_node_type
  num_cache_clusters   = 1
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.k8s.name
  security_group_ids = [aws_security_group.elasticache.id]

  preferred_cache_cluster_azs = ["ap-northeast-2c"]

  at_rest_encryption_enabled  = false
  transit_encryption_enabled  = false
  automatic_failover_enabled  = false
  multi_az_enabled            = false

  snapshot_retention_limit = 0
  snapshot_window          = "01:30-02:30"
  maintenance_window       = "thu:06:00-thu:07:00"

  auto_minor_version_upgrade = true

  tags = { Name = "refit-redis" }
}
