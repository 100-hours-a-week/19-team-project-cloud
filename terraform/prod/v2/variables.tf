# -----------------------------------------------------
# General (refit prod v2)
# -----------------------------------------------------

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_profile" {
  description = "AWS CLI profile name (사전에 설정 필수, 아래 문서 참고)"
  type        = string
  default     = "refit-terraform"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "refit"
}

variable "environment" {
  description = "Environment (prod)"
  type        = string
  default     = "prod"
}

variable "name_prefix" {
  description = "Prefix for all resource names (refit-prod-v2)"
  type        = string
  default     = "refit-prod-v2"
}

# -----------------------------------------------------
# VPC (신규 생성 또는 기존 VPC 사용)
# -----------------------------------------------------

variable "use_existing_vpc" {
  description = "true면 existing_vpc_name·existing_*_subnet_ids 사용, false면 새 VPC·서브넷 생성"
  type        = bool
  default     = true
}

variable "existing_vpc_name" {
  description = "기존 VPC 이름 (use_existing_vpc=true일 때). Name 태그로 조회"
  type        = string
  default     = "refit-prod-vpc"
}

variable "existing_public_subnet_ids" {
  description = "기존 public 서브넷 ID 목록 (ALB 등). use_existing_vpc=true일 때 필수"
  type        = list(string)
  default     = []

  validation {
    condition     = !var.use_existing_vpc || length(var.existing_public_subnet_ids) > 0
    error_message = "use_existing_vpc=true일 때 existing_public_subnet_ids를 1개 이상 지정하세요."
  }
}

variable "existing_private_backend_subnet_ids" {
  description = "기존 private backend 서브넷 ID 목록 (ASG). use_existing_vpc=true일 때 필수"
  type        = list(string)
  default     = []

  validation {
    condition     = !var.use_existing_vpc || length(var.existing_private_backend_subnet_ids) > 0
    error_message = "use_existing_vpc=true일 때 existing_private_backend_subnet_ids를 1개 이상 지정하세요."
  }
}

variable "existing_private_data_subnet_ids" {
  description = "기존 private data 서브넷 ID 목록 (RDS, ElastiCache). use_existing_vpc=true일 때 필수"
  type        = list(string)
  default     = []

  validation {
    condition     = !var.use_existing_vpc || length(var.existing_private_data_subnet_ids) > 0
    error_message = "use_existing_vpc=true일 때 existing_private_data_subnet_ids를 1개 이상 지정하세요."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (use_existing_vpc=false일 때만 사용)"
  type        = string
  default     = "10.2.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for subnets (use_existing_vpc=false일 때만 사용)"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (use_existing_vpc=false일 때만 사용)"
  type        = list(string)
  default     = ["10.2.1.0/24", "10.2.2.0/24"]
}

variable "private_backend_subnet_cidrs" {
  description = "CIDR blocks for private backend subnets (use_existing_vpc=false일 때만 사용)"
  type        = list(string)
  default     = ["10.2.10.0/24", "10.2.11.0/24"]
}

variable "private_data_subnet_cidrs" {
  description = "CIDR blocks for private data subnets (use_existing_vpc=false일 때만 사용)"
  type        = list(string)
  default     = ["10.2.20.0/24", "10.2.21.0/24"]
}

# -----------------------------------------------------
# CloudFront + WAF (설계도: Route 53 → WAF → CloudFront → ALB)
# -----------------------------------------------------

variable "cloudfront_enabled" {
  description = "CloudFront + WAF 사용 여부. true면 Route 53에서 CloudFront로 연결하는 구성을 적용한다."
  type        = bool
  default     = false
}

variable "cloudfront_aliases" {
  description = "CloudFront 대체 도메인(커스텀 도메인). Route 53/ACM과 일치시킨다. 예: [\"api.example.com\"]"
  type        = list(string)
  default     = []
}

variable "cloudfront_origin_domain" {
  description = "CloudFront 오리진 도메인. 비우면 ALB DNS 이름 사용(HTTP 오리진). 도메인 지정 시 해당 호스트가 ALB를 가리키고 ACM에 포함되어 있어야 HTTPS 오리진 가능."
  type        = string
  default     = ""
}

variable "cloudfront_acm_certificate_arn" {
  description = "CloudFront 뷰어 인증서(us-east-1 ACM). 커스텀 도메인 사용 시 필수. SSM 사용 시 비우고 ssm_parameter_cloudfront_acm_certificate_arn만 설정."
  type        = string
  default     = ""
}

variable "ssm_parameter_cloudfront_acm_certificate_arn" {
  description = "CloudFront용 ACM 인증서 ARN(us-east-1)이 저장된 SSM Parameter 경로."
  type        = string
  default     = ""
}

variable "waf_enable_managed_rules" {
  description = "WAF AWS 관리 규칙(CommonRuleSet, KnownBadInputs) 사용 여부"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "WAF IP당 분당 요청 수 제한. 0이면 비활성화."
  type        = number
  default     = 2000
}

# -----------------------------------------------------
# ALB
# -----------------------------------------------------

variable "acm_certificate_arn" {
  description = "External ALB HTTPS용 ACM 인증서 ARN. SSM 사용 시에는 비우고 ssm_parameter_acm_certificate_arn만 설정한다."
  type        = string
  default     = ""
}

# -----------------------------------------------------
# SSM Parameter Store (시크릿)
# -----------------------------------------------------

variable "ssm_parameter_acm_certificate_arn" {
  description = "ACM 인증서 ARN이 저장된 SSM Parameter 경로. 예: /refit/prod-v2/acm-certificate-arn"
  type        = string
  default     = ""
}

variable "ssm_parameter_db_username" {
  description = "RDS 마스터 사용자명이 저장된 SSM Parameter 경로. 예: /refit/prod-v2/rds/username"
  type        = string
  default     = ""
}

variable "ssm_parameter_db_password" {
  description = "RDS 마스터 비밀번호가 저장된 SSM Parameter 경로. 예: /refit/prod-v2/rds/password (SecureString 권장)"
  type        = string
  default     = ""
  sensitive   = true
}

# -----------------------------------------------------
# ASG (Backend)
# -----------------------------------------------------

variable "asg_min_size" {
  description = "Minimum number of instances in Backend ASG"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of instances in Backend ASG"
  type        = number
  default     = 2
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in Backend ASG"
  type        = number
  default     = 1
}

variable "instance_type" {
  description = "EC2 instance type for Backend ASG"
  type        = string
  default     = "t4g.medium"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30
}

# -----------------------------------------------------
# ASG (Frontend - Next.js)
# -----------------------------------------------------

variable "frontend_asg_min_size" {
  description = "Minimum number of instances in Frontend ASG"
  type        = number
  default     = 1
}

variable "frontend_asg_max_size" {
  description = "Maximum number of instances in Frontend ASG"
  type        = number
  default     = 2
}

variable "frontend_asg_desired_capacity" {
  description = "Desired number of instances in Frontend ASG"
  type        = number
  default     = 1
}

variable "frontend_instance_type" {
  description = "EC2 instance type for Frontend ASG (Next.js)"
  type        = string
  default     = "t4g.small"
}

variable "frontend_root_volume_size" {
  description = "Root EBS volume size in GB for Frontend"
  type        = number
  default     = 20
}

# -----------------------------------------------------
# RDS
# -----------------------------------------------------

variable "use_existing_rds" {
  description = "true면 기존 RDS(refit-postgres) 사용 - 서브넷 그룹/SG는 기존 것 참조"
  type        = bool
  default     = true
}

variable "db_instance_identifier" {
  description = "RDS 인스턴스 식별자 (신규: name_prefix 기반, 기존 사용 시 terraform.tfvars에서 실제 identifier 설정)"
  type        = string
  default     = "refit-prod-v2-rds"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.small"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "PostgreSQL engine version (기존: 17.7)"
  type        = string
  default     = "17.7"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "refit"
}

variable "existing_db_subnet_group_name" {
  description = "기존 RDS 사용 시 DB 서브넷 그룹 이름. use_existing_rds=true일 때 필수."
  type        = string
  default     = ""
}

variable "existing_rds_security_group_id" {
  description = "기존 RDS 사용 시 보안 그룹 ID(sg-로 시작). use_existing_rds=true일 때 필수."
  type        = string
  default     = ""
}

variable "db_username" {
  description = "RDS 마스터 사용자명. SSM을 사용하지 않을 때만 설정한다."
  type        = string
  default     = ""
  sensitive   = true
}

variable "db_password" {
  description = "RDS 마스터 비밀번호. SSM을 사용하지 않을 때만 설정한다."
  type        = string
  default     = ""
  sensitive   = true
}

# -----------------------------------------------------
# ElastiCache
# -----------------------------------------------------

variable "elasticache_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.medium"
}

variable "elasticache_num_cache_clusters" {
  description = "Number of cache nodes (2 = primary + replica per design)"
  type        = number
  default     = 2
}

# -----------------------------------------------------
# Kafka ASG (설계도: EC2 Kafka 2노드 이상)
# -----------------------------------------------------

variable "kafka_asg_min_size" {
  description = "Minimum number of Kafka EC2 instances"
  type        = number
  default     = 2
}

variable "kafka_asg_max_size" {
  description = "Maximum number of Kafka EC2 instances"
  type        = number
  default     = 4
}

variable "kafka_asg_desired_capacity" {
  description = "Desired number of Kafka EC2 instances"
  type        = number
  default     = 2
}

variable "kafka_instance_type" {
  description = "EC2 instance type for Kafka"
  type        = string
  default     = "t4g.small"
}

variable "kafka_root_volume_size" {
  description = "Root EBS volume size in GB for Kafka"
  type        = number
  default     = 30
}
