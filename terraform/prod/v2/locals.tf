# -----------------------------------------------------------------------------
# Locals: name prefix, tier 태그 상수
# -----------------------------------------------------------------------------
# 인스턴스 재시작 시 private IP가 바뀌므로, 서비스 식별은 tier 태그로 한다.
# -----------------------------------------------------------------------------

locals {
  name = var.name_prefix

  tier_backend      = "backend"
  tier_frontend     = "frontend"
  tier_kafka        = "kafka"
  tier_alb_ext      = "alb-external"
  tier_alb_int      = "alb-internal"
  tier_rds          = "rds"
  tier_rds_replica  = "rds-replica"
  tier_elasticache  = "elasticache"
  tier_deploy       = "deploy"

  # 시크릿: SSM 파라미터 경로가 지정되면 SSM에서 조회, 아니면 변수 값 사용
  db_username         = var.ssm_parameter_db_username != "" ? data.aws_ssm_parameter.db_username[0].value : var.db_username
  db_password         = var.ssm_parameter_db_password != "" ? data.aws_ssm_parameter.db_password[0].value : var.db_password
  acm_certificate_arn = var.ssm_parameter_acm_certificate_arn != "" ? data.aws_ssm_parameter.acm_certificate_arn[0].value : var.acm_certificate_arn

  # CloudFront 뷰어 인증서(us-east-1). 커스텀 도메인 사용 시에만 필요
  cloudfront_acm_arn = var.ssm_parameter_cloudfront_acm_certificate_arn != "" ? data.aws_ssm_parameter.cloudfront_acm_certificate_arn[0].value : var.cloudfront_acm_certificate_arn
}
