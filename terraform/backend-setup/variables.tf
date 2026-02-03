# -----------------------------------------------------
# General
# -----------------------------------------------------
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "refit"
}

# -----------------------------------------------------
# Backend Resources
# -----------------------------------------------------
variable "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  type        = string
  default     = "refit-terraform-state"
}

variable "lock_table_name" {
  description = "DynamoDB table name for Terraform state locking"
  type        = string
  default     = "refit-terraform-lock"
}

variable "enable_versioning" {
  description = "Enable versioning for S3 bucket"
  type        = bool
  default     = true
}
