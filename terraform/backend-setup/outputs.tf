# -----------------------------------------------------
# S3 Bucket Outputs
# -----------------------------------------------------
output "s3_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.terraform_state.arn
}

output "s3_bucket_region" {
  description = "Region of the S3 bucket"
  value       = aws_s3_bucket.terraform_state.region
}

# -----------------------------------------------------
# DynamoDB Table Outputs
# -----------------------------------------------------
output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_lock.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.terraform_lock.arn
}

# -----------------------------------------------------
# Backend Configuration Template
# -----------------------------------------------------
output "backend_config" {
  description = "Backend configuration to use in other Terraform projects"
  value = <<-EOT
    terraform {
      backend "s3" {
        bucket         = "${aws_s3_bucket.terraform_state.id}"
        key            = "ENV/terraform.tfstate"  # ENV를 dev, prod 등으로 변경
        region         = "${aws_s3_bucket.terraform_state.region}"
        encrypt        = true
        dynamodb_table = "${aws_dynamodb_table.terraform_lock.name}"
      }
    }
  EOT
}
