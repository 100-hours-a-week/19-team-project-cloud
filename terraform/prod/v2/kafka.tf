# -----------------------------------------------------
# Kafka EC2 (단일 노드, ASG 없음)
# Spring Boot와 분리된 전용 인스턴스
# -----------------------------------------------------

data "aws_ami" "prod_v2_kafka_ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

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

resource "aws_instance" "prod_v2_kafka" {
  count         = 1
  ami           = data.aws_ami.prod_v2_kafka_ubuntu.id
  instance_type = var.kafka_instance_type
  key_name      = var.key_name
  subnet_id     = local.private_backend_subnet_ids[0]
  private_ip    = var.kafka_private_ip

  iam_instance_profile   = aws_iam_instance_profile.prod_v2_kafka.name
  vpc_security_group_ids = [aws_security_group.prod_v2_kafka.id]

  root_block_device {
    volume_size           = var.kafka_root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  volume_tags = {
    Name = "${local.name}-kafka-1-root"
    tier = local.tier_kafka
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(<<-EOT
#!/bin/bash
set -e
apt-get update && apt-get install -y docker.io docker-compose-v2
systemctl enable docker && systemctl start docker
# Kafka: In-place deployment (Docker Compose 등으로 구성)
  EOT
  )

  tags = {
    Name = "${local.name}-kafka-1"
    tier = local.tier_kafka
  }
}
