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
  description = "Environment (monitoring)"
  type        = string
  default     = "monitoring"
}

# -----------------------------------------------------
# Network
# -----------------------------------------------------
variable "dev_environment" {
  description = "Name of the dev environment to reference"
  type        = string
  default     = "dev"
}

variable "monitoring_subnet_cidr" {
  description = "CIDR block for monitoring subnet"
  type        = string
  default     = "10.1.2.0/24"
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
  default     = 50
}

# -----------------------------------------------------
# Security Group
# -----------------------------------------------------
variable "allowed_ssh_cidr" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_grafana_cidr" {
  description = "CIDR blocks allowed for Grafana access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allow_public_prometheus" {
  description = "Allow public access to Prometheus (9090)"
  type        = bool
  default     = false
}

variable "allow_public_loki" {
  description = "Allow public access to Loki (3100)"
  type        = bool
  default     = false
}
