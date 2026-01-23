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

variable "environment" {
  description = "Environment (prod, dev, staging)"
  type        = string
  default     = "prod"
}

# -----------------------------------------------------
# VPC
# -----------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Availability zone for subnet"
  type        = string
  default     = "ap-northeast-2a"
}

# -----------------------------------------------------
# EC2
# -----------------------------------------------------
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t4g.medium"
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "root_volume_size" {
  description = "Size of root EBS volume in GB"
  type        = number
  default     = 30
}

# -----------------------------------------------------
# Security Group
# -----------------------------------------------------
variable "allowed_ssh_cidr" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_db_cidr" {
  description = "CIDR blocks allowed for PostgreSQL access"
  type        = list(string)
  default     = []
}
