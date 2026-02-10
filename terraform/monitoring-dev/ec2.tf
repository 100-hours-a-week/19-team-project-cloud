# -----------------------------------------------------
# EC2 Instance - Monitoring Server
# -----------------------------------------------------
resource "aws_instance" "monitoring" {
  ami                    = data.aws_ami.ubuntu_arm64.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.monitoring.id
  vpc_security_group_ids = [aws_security_group.monitoring.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-${var.environment}-root-volume"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 강제
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-server"
  }

  lifecycle {
    ignore_changes = [ami] # AMI 업데이트로 인한 재생성 방지
  }
}

# -----------------------------------------------------
# Elastic IP
# -----------------------------------------------------
resource "aws_eip" "monitoring" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-eip"
  }
}

resource "aws_eip_association" "monitoring" {
  instance_id   = aws_instance.monitoring.id
  allocation_id = aws_eip.monitoring.id
}
