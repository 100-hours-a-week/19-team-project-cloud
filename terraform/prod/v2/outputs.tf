# -----------------------------------------------------
# Outputs (refit-prod-v2)
# -----------------------------------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = local.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = local.public_subnet_ids
}

output "private_backend_subnet_ids" {
  description = "Private Backend subnet IDs"
  value       = local.private_backend_subnet_ids
}

output "private_data_subnet_ids" {
  description = "Private Data subnet IDs"
  value       = local.private_data_subnet_ids
}

output "external_alb_dns_name" {
  description = "External ALB DNS name"
  value       = aws_lb.prod_v2_external.dns_name
}

output "external_alb_zone_id" {
  description = "External ALB zone ID (for Route53 alias)"
  value       = aws_lb.prod_v2_external.zone_id
}

output "backend_target_group_arn" {
  description = "Backend target group ARN"
  value       = aws_lb_target_group.prod_v2_backend.arn
}

output "frontend_target_group_arn" {
  description = "Frontend target group ARN"
  value       = aws_lb_target_group.prod_v2_frontend.arn
}

output "rds_endpoint" {
  description = "RDS primary endpoint"
  value       = aws_db_instance.prod_v2.address
  sensitive   = true
}

output "rds_replica_endpoint" {
  description = "RDS read replica endpoint (use_existing_rds=true면 null)"
  value       = length(aws_db_instance.prod_v2_replica) > 0 ? aws_db_instance.prod_v2_replica[0].address : null
  sensitive   = true
}

output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint (Backend 연결용, rds_proxy_enabled=true일 때)"
  value       = var.rds_proxy_enabled ? aws_db_proxy.prod_v2[0].endpoint : null
  sensitive   = true
}

output "elasticache_primary_endpoint" {
  description = "ElastiCache primary endpoint"
  value       = aws_elasticache_replication_group.prod_v2.primary_endpoint_address
  sensitive   = true
}

output "codedeploy_app_name" {
  description = "CodeDeploy Backend application name"
  value       = aws_codedeploy_app.prod_v2_backend.name
}

output "codedeploy_deployment_group_name" {
  description = "CodeDeploy Backend deployment group name"
  value       = aws_codedeploy_deployment_group.prod_v2_backend.deployment_group_name
}

output "codedeploy_backend_app_name" {
  description = "CodeDeploy Backend application name"
  value       = aws_codedeploy_app.prod_v2_backend.name
}

output "codedeploy_backend_deployment_group_name" {
  description = "CodeDeploy Backend deployment group name"
  value       = aws_codedeploy_deployment_group.prod_v2_backend.deployment_group_name
}

output "codedeploy_frontend_app_name" {
  description = "CodeDeploy Frontend application name"
  value       = aws_codedeploy_app.prod_v2_frontend.name
}

output "codedeploy_frontend_deployment_group_name" {
  description = "CodeDeploy Frontend deployment group name"
  value       = aws_codedeploy_deployment_group.prod_v2_frontend.deployment_group_name
}

output "deploy_s3_bucket" {
  description = "S3 bucket for CodeDeploy artifacts"
  value       = aws_s3_bucket.prod_v2_deployments.id
}

output "backend_asg_name" {
  description = "Backend ASG name"
  value       = aws_autoscaling_group.prod_v2_backend.name
}

output "kafka_instance_ids" {
  description = "Kafka EC2 instance IDs"
  value       = aws_instance.prod_v2_kafka[*].id
}

output "ai_instance_id" {
  description = "AI EC2 instance ID"
  value       = aws_instance.prod_v2_ai.id
}

output "monitoring_instance_id" {
  description = "Monitoring EC2 instance ID"
  value       = aws_instance.prod_v2_monitoring.id
}

output "ai_target_group_arn" {
  description = "AI target group ARN"
  value       = aws_lb_target_group.prod_v2_ai.arn
}

output "monitoring_target_group_arn" {
  description = "Monitoring target group ARN"
  value       = aws_lb_target_group.prod_v2_monitoring.arn
}

output "codedeploy_ai_app_name" {
  description = "CodeDeploy AI application name"
  value       = aws_codedeploy_app.prod_v2_ai.name
}

# -----------------------------------------------------
# CloudFront + WAF (cloudfront_enabled=true일 때)
# -----------------------------------------------------

output "cloudfront_domain_name" {
  description = "CloudFront 배포 도메인 (Route 53 CNAME/alias 타깃)"
  value       = var.cloudfront_enabled ? aws_cloudfront_distribution.prod_v2[0].domain_name : null
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront 배포 Hosted Zone ID (Route 53 alias 레코드용)"
  value       = var.cloudfront_enabled ? aws_cloudfront_distribution.prod_v2[0].hosted_zone_id : null
}

output "cloudfront_distribution_arn" {
  description = "CloudFront 배포 ARN"
  value       = var.cloudfront_enabled ? aws_cloudfront_distribution.prod_v2[0].arn : null
}

output "cloudfront_distribution_id" {
  description = "CloudFront 배포 ID (캐시 무효화 등)"
  value       = var.cloudfront_enabled ? aws_cloudfront_distribution.prod_v2[0].id : null
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN (CloudFront 연동)"
  value       = var.cloudfront_enabled ? aws_wafv2_web_acl.prod_v2[0].arn : null
}
