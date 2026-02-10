# -----------------------------------------------------
# IAM Role for EC2
# -----------------------------------------------------
resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2-role"
  }
}

# -----------------------------------------------------
# ECR Read-Only Policy
# -----------------------------------------------------
resource "aws_iam_role_policy" "ecr_read" {
  name = "${var.project_name}-${var.environment}-ecr-read"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = [
          "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.project_name}-*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------
# Instance Profile
# -----------------------------------------------------
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# -----------------------------------------------------
# Data source for account ID
# -----------------------------------------------------
data "aws_caller_identity" "current" {}
