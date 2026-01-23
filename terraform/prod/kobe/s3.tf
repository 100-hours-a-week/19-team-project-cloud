# -----------------------------------------------------
# S3 Bucket for Application Files
# -----------------------------------------------------
resource "aws_s3_bucket" "app_files" {
  bucket = "${var.project_name}-${var.environment}-files"

  tags = {
    Name = "${var.project_name}-${var.environment}-files"
    Type = "application-storage"
  }
}

# -----------------------------------------------------
# Bucket Versioning
# -----------------------------------------------------
resource "aws_s3_bucket_versioning" "app_files" {
  bucket = aws_s3_bucket.app_files.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------
# Server-Side Encryption
# -----------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "app_files" {
  bucket = aws_s3_bucket.app_files.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# -----------------------------------------------------
# Public Access Block Settings
# -----------------------------------------------------
resource "aws_s3_bucket_public_access_block" "app_files" {
  bucket = aws_s3_bucket.app_files.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# -----------------------------------------------------
# Bucket Policy for Public Read Access
# -----------------------------------------------------
resource "aws_s3_bucket_policy" "app_files" {
  bucket = aws_s3_bucket.app_files.id

  depends_on = [aws_s3_bucket_public_access_block.app_files]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.app_files.arn}/*"
      }
    ]
  })
}

# -----------------------------------------------------
# CORS Configuration
# -----------------------------------------------------
resource "aws_s3_bucket_cors_configuration" "app_files" {
  bucket = aws_s3_bucket.app_files.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", "PUT", "POST"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# -----------------------------------------------------
# Lifecycle Rules (Optional - Delete old versions)
# -----------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "app_files" {
  bucket = aws_s3_bucket.app_files.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  rule {
    id     = "abort-incomplete-multipart-upload"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
