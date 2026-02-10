# -----------------------------------------------------
# Terraform Backend (S3 + DynamoDB)
# -----------------------------------------------------
terraform {
  backend "s3" {
    bucket         = "refit-terraform-state"
    key            = "monitoring-dev/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "refit-terraform-lock"
    encrypt        = true
  }
}
