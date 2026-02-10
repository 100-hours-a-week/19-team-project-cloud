# -----------------------------------------------------------------------------
# SSM Parameter Store
# -----------------------------------------------------------------------------
# 본 모듈에서 사용하는 시크릿(ACM ARN, RDS 사용자명·비밀번호)을 Parameter Store에서
# 조회한다. 파라미터는 사전에 생성되어 있어야 하며, Terraform 실행 IAM에
# ssm:GetParameter, ssm:GetParameters 권한이 필요하다.
# -----------------------------------------------------------------------------

data "aws_ssm_parameter" "db_username" {
  count           = var.ssm_parameter_db_username != "" ? 1 : 0
  name            = var.ssm_parameter_db_username
  with_decryption = true
}

data "aws_ssm_parameter" "db_password" {
  count           = var.ssm_parameter_db_password != "" ? 1 : 0
  name            = var.ssm_parameter_db_password
  with_decryption = true
}

data "aws_ssm_parameter" "acm_certificate_arn" {
  count = var.ssm_parameter_acm_certificate_arn != "" ? 1 : 0
  name  = var.ssm_parameter_acm_certificate_arn
}

# CloudFront 뷰어 인증서(us-east-1 ACM ARN). 파라미터 값은 ARN 문자열만 저장하면 됨
data "aws_ssm_parameter" "cloudfront_acm_certificate_arn" {
  count = var.ssm_parameter_cloudfront_acm_certificate_arn != "" ? 1 : 0
  name  = var.ssm_parameter_cloudfront_acm_certificate_arn
}
