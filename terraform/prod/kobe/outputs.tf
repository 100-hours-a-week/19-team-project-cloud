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
# Ansible Inventory Output
# -----------------------------------------------------
output "ansible_inventory" {
  description = "Ansible inventory entry"
  value       = <<-EOT
    [refit_servers]
    ${aws_eip.main.public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/${var.key_name}.pem
  EOT
}

# -----------------------------------------------------
# SSH Connection
# -----------------------------------------------------
output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_eip.main.public_ip}"
}

# -----------------------------------------------------
# S3 Outputs
# -----------------------------------------------------
output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.app_files.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.app_files.arn
}

output "s3_bucket_domain" {
  description = "Domain name of the S3 bucket"
  value       = aws_s3_bucket.app_files.bucket_domain_name
}

output "s3_bucket_url" {
  description = "URL of the S3 bucket"
  value       = "https://${aws_s3_bucket.app_files.bucket_domain_name}"
}
