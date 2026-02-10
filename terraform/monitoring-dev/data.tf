# -----------------------------------------------------
# Data Sources - Reference Dev Environment
# -----------------------------------------------------

# Dev VPC 참조
data "aws_vpc" "dev" {
  tags = {
    Project     = var.project_name
    Environment = var.dev_environment
  }
}

# Dev 인터넷 게이트웨이 참조
data "aws_internet_gateway" "dev" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.dev.id]
  }
}

# Dev 애플리케이션 서버 참조 (보안 그룹 규칙에 사용)
data "aws_instance" "dev_app" {
  filter {
    name   = "tag:Name"
    values = ["${var.project_name}-${var.dev_environment}-server"]
  }

  filter {
    name   = "instance-state-name"
    values = ["running", "stopped"]
  }
}

# Ubuntu 22.04 LTS ARM64 AMI 조회 (최신)
data "aws_ami" "ubuntu_arm64" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}
