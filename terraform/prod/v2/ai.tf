# AI EC2 instance (standalone, no ASG)
resource "aws_instance" "prod_v2_ai" {
  ami           = data.aws_ami.prod_v2_ubuntu.id
  instance_type = var.ai_instance_type
  key_name      = var.key_name
  subnet_id     = local.private_backend_subnet_ids[0]

  iam_instance_profile   = data.aws_iam_instance_profile.refit_ec2_ssm.name
  vpc_security_group_ids = [aws_security_group.prod_v2_ai.id]

  root_block_device {
    volume_size           = var.ai_root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
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
usermod -aG docker ubuntu
cd /tmp && wget https://aws-codedeploy-${var.aws_region}.s3.${var.aws_region}.amazonaws.com/latest/install
chmod +x install && ./install auto
  EOT
  )

  volume_tags = {
    Name = "${local.name}-ai-root"
    tier = local.tier_ai
  }

  tags = {
    Name = "${local.name}-ai"
    tier = local.tier_ai
  }
}
