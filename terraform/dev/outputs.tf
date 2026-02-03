# -----------------------------------------------------
# VPC Outputs
# -----------------------------------------------------
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

# -----------------------------------------------------
# Security Group Outputs
# -----------------------------------------------------
output "security_group_id" {
  description = "ID of the main security group"
  value       = aws_security_group.main.id
}

# -----------------------------------------------------
# EC2 Outputs
# -----------------------------------------------------
output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.main.id
}

output "instance_private_ip" {
  description = "Private IP of the EC2 instance"
  value       = aws_instance.main.private_ip
}

output "elastic_ip" {
  description = "Elastic IP address"
  value       = aws_eip.main.public_ip
}

# -----------------------------------------------------
# SSH Connection
# -----------------------------------------------------
output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_eip.main.public_ip}"
}
