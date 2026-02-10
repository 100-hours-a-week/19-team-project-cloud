# -----------------------------------------------------
# VPC Outputs
# -----------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC (from dev)"
  value       = data.aws_vpc.dev.id
}

output "monitoring_subnet_id" {
  description = "ID of the monitoring subnet"
  value       = aws_subnet.monitoring.id
}

# -----------------------------------------------------
# Security Group Outputs
# -----------------------------------------------------
output "security_group_id" {
  description = "ID of the monitoring security group"
  value       = aws_security_group.monitoring.id
}

# -----------------------------------------------------
# EC2 Outputs
# -----------------------------------------------------
output "instance_id" {
  description = "ID of the monitoring EC2 instance"
  value       = aws_instance.monitoring.id
}

output "instance_private_ip" {
  description = "Private IP of the monitoring EC2 instance"
  value       = aws_instance.monitoring.private_ip
}

output "elastic_ip" {
  description = "Elastic IP address of monitoring server"
  value       = aws_eip.monitoring.public_ip
}

# -----------------------------------------------------
# Application Server Reference
# -----------------------------------------------------
output "dev_app_server_private_ip" {
  description = "Private IP of dev application server"
  value       = data.aws_instance.dev_app.private_ip
}

# -----------------------------------------------------
# Service URLs
# -----------------------------------------------------
output "grafana_url" {
  description = "Grafana web UI URL"
  value       = "http://${aws_eip.monitoring.public_ip}:3000"
}

output "prometheus_url" {
  description = "Prometheus web UI URL"
  value       = "http://${aws_eip.monitoring.public_ip}:9090"
}

output "loki_url" {
  description = "Loki API URL"
  value       = "http://${aws_eip.monitoring.public_ip}:3100"
}

# -----------------------------------------------------
# SSH Connection
# -----------------------------------------------------
output "ssh_command" {
  description = "SSH command to connect to the monitoring server"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_eip.monitoring.public_ip}"
}

# -----------------------------------------------------
# Next Steps
# -----------------------------------------------------
output "next_steps" {
  description = "Next steps to configure monitoring"
  value = <<-EOT

  Monitoring server created successfully!

  1. SSH into the server:
     ${format("ssh -i ~/.ssh/%s.pem ubuntu@%s", var.key_name, aws_eip.monitoring.public_ip)}

  2. Install Docker and Docker Compose:
     sudo apt update && sudo apt install -y docker.io docker-compose-v2
     sudo usermod -aG docker ubuntu

  3. Configure monitoring stack (refer to OBSERVABILITY_GUIDE.md):
     - Create docker-compose.yml with Loki, Prometheus, Grafana
     - Create configuration files for each service
     - Update Prometheus targets with app server IP: ${data.aws_instance.dev_app.private_ip}

  4. Access services:
     - Grafana: http://${aws_eip.monitoring.public_ip}:3000
     - Prometheus: http://${aws_eip.monitoring.public_ip}:9090 (if enabled)

  5. Update application server security group to allow metrics scraping from: ${aws_instance.monitoring.private_ip}

  EOT
}
