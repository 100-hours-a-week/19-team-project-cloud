# -----------------------------------------------------
# Terraform & AWS Provider (refit prod v2)
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
      Version     = "v2"
      ManagedBy   = "terraform"
    }
  }
}

# CloudFront 연동 WAF는 scope=CLOUDFRONT이므로 us-east-1에 생성해야 함
provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Version     = "v2"
      ManagedBy   = "terraform"
    }
  }
}
