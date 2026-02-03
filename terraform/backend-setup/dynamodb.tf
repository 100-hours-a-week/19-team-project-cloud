# -----------------------------------------------------
# DynamoDB Table for Terraform State Locking
# -----------------------------------------------------
resource "aws_dynamodb_table" "terraform_lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST" # 온디맨드 요금제 (사용량 기반)
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = var.lock_table_name
    Description = "Terraform state locking"
  }

  lifecycle {
    prevent_destroy = true # 실수로 삭제 방지
  }
}
