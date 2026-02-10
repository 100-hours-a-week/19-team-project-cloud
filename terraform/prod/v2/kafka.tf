# -----------------------------------------------------
# Kafka ASG (설계도: EC2 Kafka 2노드 이상, A/C Zone)
# In-place deployment, Docker 위에서 Kafka 운영
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

resource "aws_launch_template" "prod_v2_kafka" {
  name_prefix   = "${local.name}-kafka-"
  image_id      = data.aws_ami.prod_v2_kafka_ubuntu.id
  instance_type = var.kafka_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.prod_v2_kafka.name
  }

  vpc_security_group_ids = [aws_security_group.prod_v2_kafka.id]

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = var.kafka_root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
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

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name}-kafka"
      tier = local.tier_kafka
    }
  }

  tags = {
    Name = "${local.name}-kafka-lt"
    tier = local.tier_kafka
  }
}

resource "aws_autoscaling_group" "prod_v2_kafka" {
  name                = "${local.name}-kafka-asg"
  vpc_zone_identifier = local.private_backend_subnet_ids
  health_check_type   = "EC2"
  health_check_grace_period = 180

  min_size         = var.kafka_asg_min_size
  max_size         = var.kafka_asg_max_size
  desired_capacity = var.kafka_asg_desired_capacity

  launch_template {
    id      = aws_launch_template.prod_v2_kafka.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-kafka"
    propagate_at_launch = true
  }

  tag {
    key                 = "refit-prod-v2"
    value               = "kafka"
    propagate_at_launch = true
  }

  tag {
    key                 = "tier"
    value               = local.tier_kafka
    propagate_at_launch = true
  }
}
