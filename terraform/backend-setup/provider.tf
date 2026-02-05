terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # 이 프로젝트는 로컬 백엔드 사용 (원격 백엔드 리소스를 생성하기 위함)
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "refit"
      Environment = "backend"
      ManagedBy   = "terraform"
      Purpose     = "terraform-state-management"
    }
  }
}
