# Monitoring EC2 instance (Grafana, Prometheus, Loki, Tempo, etc.)
resource "aws_instance" "prod_v2_monitoring" {
  ami           = data.aws_ami.prod_v2_ubuntu.id
  instance_type = var.monitoring_instance_type
  key_name      = var.key_name
  subnet_id     = local.monitoring_subnet_id

  iam_instance_profile   = data.aws_iam_instance_profile.refit_ec2_ssm.name
  vpc_security_group_ids = [aws_security_group.prod_v2_monitoring.id]

  root_block_device {
    volume_size           = var.monitoring_root_volume_size
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
apt-get update && apt-get install -y docker.io docker-compose-v2
systemctl enable docker && systemctl start docker
usermod -aG docker ubuntu
  EOT
  )

  volume_tags = {
    Name = "${local.name}-monitoring-root"
    tier = local.tier_monitoring
  }

  tags = {
    Name = "refit-prod-monitoring"
    tier = local.tier_monitoring
  }
}
