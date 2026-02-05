terraform {
  backend "s3" {
    bucket         = "refit-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "ap-northeast-2"
    encrypt        = true
    dynamodb_table = "refit-terraform-lock"
  }
}
