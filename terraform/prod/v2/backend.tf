# -----------------------------------------------------
# Terraform Backend (backend-setup S3/DynamoDB 사용)
# -----------------------------------------------------
terraform {
  backend "s3" {
    bucket         = "refit-terraform-state"
    key            = "prod/v2/terraform.tfstate"
    region         = "ap-northeast-2"
    encrypt        = true
    dynamodb_table = "refit-terraform-lock"
  }
}
