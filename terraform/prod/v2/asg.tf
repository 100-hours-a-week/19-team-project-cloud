# -----------------------------------------------------
# Backend ASG (refit-prod-v2), Min 1 / Max 2
# -----------------------------------------------------

data "aws_ami" "prod_v2_ubuntu" {
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

resource "aws_launch_template" "prod_v2_backend" {
  name_prefix   = "${local.name}-backend-"
  image_id      = data.aws_ami.prod_v2_ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = data.aws_iam_instance_profile.refit_ec2_ssm.name
  }

  vpc_security_group_ids = [aws_security_group.prod_v2_backend.id]

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = var.root_volume_size
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
apt-get update && apt-get install -y docker.io docker-compose-v2 ruby-full wget
systemctl enable docker && systemctl start docker
# CodeDeploy agent
cd /tmp && wget https://aws-codedeploy-${var.aws_region}.s3.${var.aws_region}.amazonaws.com/latest/install
chmod +x install && ./install auto
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name}-backend"
      tier = local.tier_backend
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${local.name}-backend-root"
      tier = local.tier_backend
    }
  }

  tags = {
    Name = "${local.name}-backend-lt"
    tier = local.tier_backend
  }
}

resource "aws_autoscaling_group" "prod_v2_backend" {
  name                = "${local.name}-backend-asg"
  vpc_zone_identifier = local.private_backend_subnet_ids
  target_group_arns   = [aws_lb_target_group.prod_v2_backend.arn, aws_lb_target_group.prod_v2_backend_internal.arn]
  health_check_type   = "EC2" # 앱 배포 전까지는 EC2 사용 (ELB→8080/actuator/health 실패 시 인스턴스 교체 반복)
  health_check_grace_period = 120

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  launch_template {
    id      = aws_launch_template.prod_v2_backend.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-backend"
    propagate_at_launch = true
  }

  tag {
    key                 = "refit-prod-v2"
    value               = "backend"
    propagate_at_launch = true
  }

  tag {
    key                 = "tier"
    value               = local.tier_backend
    propagate_at_launch = true
  }
}

# -----------------------------------------------------
# Frontend ASG (Next.js), Min 1 / Max 2
# -----------------------------------------------------

resource "aws_launch_template" "prod_v2_frontend" {
  name_prefix   = "${local.name}-frontend-"
  image_id      = data.aws_ami.prod_v2_ubuntu.id
  instance_type = var.frontend_instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = data.aws_iam_instance_profile.refit_ec2_ssm.name
  }

  vpc_security_group_ids = [aws_security_group.prod_v2_frontend.id]

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = var.frontend_root_volume_size
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
apt-get update && apt-get install -y docker.io docker-compose-v2 ruby-full wget
systemctl enable docker && systemctl start docker
# CodeDeploy agent
cd /tmp && wget https://aws-codedeploy-${var.aws_region}.s3.${var.aws_region}.amazonaws.com/latest/install
chmod +x install && ./install auto
  EOT
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name}-frontend"
      tier = local.tier_frontend
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${local.name}-frontend-root"
      tier = local.tier_frontend
    }
  }

  tags = {
    Name = "${local.name}-frontend-lt"
    tier = local.tier_frontend
  }
}

resource "aws_autoscaling_group" "prod_v2_frontend" {
  name                = "${local.name}-frontend-asg"
  vpc_zone_identifier = local.private_backend_subnet_ids
  target_group_arns   = [aws_lb_target_group.prod_v2_frontend.arn]
  health_check_type   = "EC2" # 앱 배포 전까지는 EC2 사용 (ELB→3000/ 실패 시 인스턴스 교체 반복)
  health_check_grace_period = 120

  min_size         = var.frontend_asg_min_size
  max_size         = var.frontend_asg_max_size
  desired_capacity = var.frontend_asg_desired_capacity

  launch_template {
    id      = aws_launch_template.prod_v2_frontend.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name}-frontend"
    propagate_at_launch = true
  }

  tag {
    key                 = "refit-prod-v2"
    value               = "frontend"
    propagate_at_launch = true
  }

  tag {
    key                 = "tier"
    value               = local.tier_frontend
    propagate_at_launch = true
  }
}
