# -----------------------------------------------------
# Variables (refit prod v3 - self-managed K8s)
# -----------------------------------------------------

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_profile" {
  description = "AWS CLI profile"
  type        = string
  default     = "refit-ssm"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "refit"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

# ------- VPC -------
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.2.0.0/16"
}

variable "subnet_pub_a_cidr" {
  description = "Public subnet CIDR - ap-northeast-2a"
  type        = string
  default     = "10.2.1.0/24"
}

variable "subnet_pub_b_cidr" {
  description = "Public subnet CIDR - ap-northeast-2b"
  type        = string
  default     = "10.2.3.0/24"
}

variable "subnet_pub_c_cidr" {
  description = "Public subnet CIDR - ap-northeast-2c"
  type        = string
  default     = "10.2.2.0/24"
}

# ------- EC2 -------
variable "key_name" {
  description = "EC2 key pair name"
  type        = string
  default     = "refit"
}

variable "master_instance_type" {
  description = "Instance type for K8s master nodes"
  type        = string
  default     = "t4g.medium"
}

variable "worker_instance_type" {
  description = "Instance type for K8s worker nodes"
  type        = string
  default     = "t4g.large"
}

variable "master_root_volume_size" {
  description = "Root EBS volume size (GiB) for master nodes"
  type        = number
  default     = 30
}

variable "worker_root_volume_size" {
  description = "Root EBS volume size (GiB) for worker nodes"
  type        = number
  default     = 50
}

# ------- SSH Allowlist -------
# 민감 정보: default 없음 → terraform.tfvars 또는 환경변수로 주입
variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed SSH access to all nodes (e.g. [\"1.2.3.4/32\"])"
  type        = list(string)
}

variable "ssh_allowed_cidrs_master_extra" {
  description = "Additional CIDRs allowed SSH access to master nodes only"
  type        = list(string)
  default     = []
}

# ------- MSK -------
variable "kafka_version" {
  description = "MSK Kafka version"
  type        = string
  default     = "3.7.x"
}

variable "kafka_broker_instance_type" {
  description = "MSK broker instance type"
  type        = string
  default     = "kafka.t3.small"
}

variable "kafka_broker_count" {
  description = "Number of MSK broker nodes"
  type        = number
  default     = 2
}

variable "kafka_ebs_volume_size" {
  description = "MSK broker EBS volume size (GiB)"
  type        = number
  default     = 20
}

# ------- ElastiCache -------
variable "elasticache_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.micro"
}

variable "elasticache_engine_version" {
  description = "Valkey engine version"
  type        = string
  default     = "8.0"
}

# ------- ALB -------
variable "alb_nodeport" {
  description = "NodePort exposed on workers for app traffic (Cilium Gateway)"
  type        = number
  default     = 30080
}

variable "alb_target_port" {
  description = "NodePort registered in ALB target group (Cilium Gateway NodePort)"
  type        = number
  default     = 32678
}

# ------- Domain -------
variable "domain_name" {
  description = "Root domain name"
  type        = string
  default     = "re-fit.kr"
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for re-fit.kr"
  type        = string
  # 민감 정보: default 없음 → terraform.tfvars로 주입
}

# ------- VPC Peering (to prod-v2) -------
variable "prod_v2_vpc_id" {
  description = "prod-v2 VPC ID to peer with (for RDS/Redis access)"
  type        = string
  # 민감 정보: default 없음 → terraform.tfvars로 주입
}

variable "prod_v2_vpc_cidr" {
  description = "prod-v2 VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}
