# -----------------------------------------------------
# IAM Roles (refit-prod-v2)
# -----------------------------------------------------

data "aws_caller_identity" "prod_v2" {}

# -----------------------------------------------------
# Backend EC2 Role (ECR, S3, SSM, CodeDeploy agent)
# -----------------------------------------------------

resource "aws_iam_role" "prod_v2_backend_ec2" {
  name = "${var.name_prefix}-backend-ec2-role"

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
    Name = "${var.name_prefix}-backend-ec2-role"
  }
}

resource "aws_iam_role_policy" "prod_v2_backend_ec2_ecr" {
  name = "${var.name_prefix}-backend-ec2-ecr"
  role = aws_iam_role.prod_v2_backend_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.prod_v2.account_id}:repository/${var.project_name}-*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "prod_v2_backend_ec2_ssm" {
  role       = aws_iam_role.prod_v2_backend_ec2.name
  policy_arn = "arn:aws:iam::aws:policy:AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "prod_v2_backend_ec2_ssm_read" {
  role       = aws_iam_role.prod_v2_backend_ec2.name
  policy_arn = "arn:aws:iam::aws:policy:AmazonSSMReadOnlyAccess"
}

resource "aws_iam_role_policy" "prod_v2_backend_ec2_s3_deploy" {
  name = "${var.name_prefix}-backend-ec2-s3-deploy"
  role = aws_iam_role.prod_v2_backend_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.prod_v2_deployments.arn,
          "${aws_s3_bucket.prod_v2_deployments.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "prod_v2_backend" {
  name = "${var.name_prefix}-backend-profile"
  role = aws_iam_role.prod_v2_backend_ec2.name
}

# -----------------------------------------------------
# Frontend EC2 Role (Next.js - ECR, S3, SSM, CodeDeploy agent)
# -----------------------------------------------------

resource "aws_iam_role" "prod_v2_frontend_ec2" {
  name = "${var.name_prefix}-frontend-ec2-role"

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
    Name = "${var.name_prefix}-frontend-ec2-role"
  }
}

resource "aws_iam_role_policy" "prod_v2_frontend_ec2_ecr" {
  name = "${var.name_prefix}-frontend-ec2-ecr"
  role = aws_iam_role.prod_v2_frontend_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.prod_v2.account_id}:repository/${var.project_name}-*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "prod_v2_frontend_ec2_ssm" {
  role       = aws_iam_role.prod_v2_frontend_ec2.name
  policy_arn = "arn:aws:iam::aws:policy:AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "prod_v2_frontend_ec2_s3_deploy" {
  name = "${var.name_prefix}-frontend-ec2-s3-deploy"
  role = aws_iam_role.prod_v2_frontend_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.prod_v2_deployments.arn,
          "${aws_s3_bucket.prod_v2_deployments.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "prod_v2_frontend" {
  name = "${var.name_prefix}-frontend-profile"
  role = aws_iam_role.prod_v2_frontend_ec2.name
}

# -----------------------------------------------------
# Kafka EC2 Role (ECR, SSM)
# -----------------------------------------------------

resource "aws_iam_role" "prod_v2_kafka_ec2" {
  name = "${var.name_prefix}-kafka-ec2-role"

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
    Name = "${var.name_prefix}-kafka-ec2-role"
  }
}

resource "aws_iam_role_policy" "prod_v2_kafka_ec2_ecr" {
  name = "${var.name_prefix}-kafka-ec2-ecr"
  role = aws_iam_role.prod_v2_kafka_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.prod_v2.account_id}:repository/${var.project_name}-*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "prod_v2_kafka_ec2_ssm" {
  role       = aws_iam_role.prod_v2_kafka_ec2.name
  policy_arn = "arn:aws:iam::aws:policy:AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "prod_v2_kafka" {
  name = "${var.name_prefix}-kafka-profile"
  role = aws_iam_role.prod_v2_kafka_ec2.name
}

# -----------------------------------------------------
# CodeDeploy Service Role
# -----------------------------------------------------

resource "aws_iam_role" "prod_v2_codedeploy" {
  name = "${var.name_prefix}-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-codedeploy-role"
  }
}

resource "aws_iam_role_policy_attachment" "prod_v2_codedeploy" {
  role       = aws_iam_role.prod_v2_codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy:service-role/AWSCodeDeployRole"
}
