# -----------------------------------------------------
# Terraform Remote State Backend (S3 + DynamoDB)
# -----------------------------------------------------
terraform {
  backend "s3" {
    bucket         = "refit-terraform-state"
    key            = "prod/v3/terraform.tfstate"
    region         = "ap-northeast-2"
    profile        = "refit-ssm"
    dynamodb_table = "refit-terraform-lock"
    encrypt        = true
  }
}
