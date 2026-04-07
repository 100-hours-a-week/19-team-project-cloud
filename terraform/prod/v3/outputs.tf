# -----------------------------------------------------
# Outputs (refit prod v3 - self-managed K8s)
# -----------------------------------------------------

# ------- VPC -------
output "vpc_id" {
  description = "K8s VPC ID"
  value       = aws_vpc.k8s.id
}

output "subnet_ids" {
  description = "Public subnet IDs (pub_a, pub_b, pub_c)"
  value = {
    pub_a = aws_subnet.pub_a.id
    pub_b = aws_subnet.pub_b.id
    pub_c = aws_subnet.pub_c.id
  }
}

# ------- EC2 -------
output "master_public_ips" {
  description = "Master node public IPs"
  value = {
    for k, v in aws_instance.master : k => v.public_ip
  }
}

output "master_private_ips" {
  description = "Master node private IPs"
  value = {
    for k, v in aws_instance.master : k => v.private_ip
  }
}

output "worker_public_ips" {
  description = "Worker node public IPs"
  value = {
    for k, v in aws_instance.worker : k => v.public_ip
  }
}

output "worker_instance_ids" {
  description = "Worker node instance IDs"
  value = {
    for k, v in aws_instance.worker : k => v.id
  }
}

# ------- NLB (Control Plane) -------
output "cp_nlb_dns" {
  description = "Control Plane NLB DNS name (use as k8sServiceHost in Cilium)"
  value       = aws_lb.cp.dns_name
}

output "cp_nlb_arn" {
  description = "Control Plane NLB ARN"
  value       = aws_lb.cp.arn
}

# ------- ALB (App) -------
output "app_alb_dns" {
  description = "App ALB DNS name"
  value       = aws_lb.app.dns_name
}

output "app_alb_arn" {
  description = "App ALB ARN"
  value       = aws_lb.app.arn
}

# ------- MSK -------
output "msk_bootstrap_brokers" {
  description = "MSK Kafka plaintext bootstrap broker string"
  value       = aws_msk_cluster.kafka.bootstrap_brokers
}

output "msk_cluster_arn" {
  description = "MSK Cluster ARN"
  value       = aws_msk_cluster.kafka.arn
}

# ------- ElastiCache -------
output "redis_primary_endpoint" {
  description = "Valkey/Redis primary endpoint"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_port" {
  description = "Valkey/Redis port"
  value       = 6379
}

# ------- DNS -------
output "dns_records" {
  description = "DNS records created"
  value = {
    api_k8s    = "api-k8s.${var.domain_name}"
    argocd     = "argocd.${var.domain_name}"
    monitoring = "monitoring.${var.domain_name}"
  }
}

# ------- IAM -------
output "ec2_instance_profile_name" {
  description = "IAM instance profile name for K8s nodes"
  value       = aws_iam_instance_profile.ec2_ssm.name
}

# ------- Security Groups -------
output "security_group_ids" {
  description = "Security group IDs"
  value = {
    alb          = aws_security_group.alb.id
    master       = aws_security_group.master.id
    worker       = aws_security_group.worker.id
    msk          = aws_security_group.msk.id
    elasticache  = aws_security_group.elasticache.id
  }
}
