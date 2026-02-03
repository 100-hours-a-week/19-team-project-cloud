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
# ECR
# -----------------------------------------------------
variable "ecr_services" {
  description = "List of services that need ECR repositories"
  type        = list(string)
  default     = ["ai", "frontend", "backend"]
}

variable "ecr_image_retention_count" {
  description = "Number of images to retain in ECR"
  type        = number
  default     = 30
}
