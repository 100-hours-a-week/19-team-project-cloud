# -----------------------------------------------------
# Terraform & AWS Provider (refit prod v3 - self-managed K8s)
# -----------------------------------------------------
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Version     = "v3"
      ManagedBy   = "terraform"
    }
  }
}
