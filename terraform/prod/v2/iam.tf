# -----------------------------------------------------
# IAM Roles (refit-prod-v2)
# -----------------------------------------------------

data "aws_caller_identity" "prod_v2" {}

# -----------------------------------------------------
# Backend/Frontend EC2 공통 IAM 역할 (RefitEC2SSMRole)
# - 역할은 data로 참조, 필요한 정책만 별도 설정 (최소 권한)
# -----------------------------------------------------

data "aws_iam_role" "refit_ec2_ssm" {
  name = var.ec2_iam_role_name
}

data "aws_iam_instance_profile" "refit_ec2_ssm" {
  name = var.ec2_iam_instance_profile_name
}

# --- AWS 관리형 정책 (SSM, CodeDeploy, CloudWatch) ---
resource "aws_iam_role_policy_attachment" "refit_ec2_ssm_managed_core" {
  role       = data.aws_iam_role.refit_ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "refit_ec2_ssm_read" {
  role       = data.aws_iam_role.refit_ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "refit_ec2_ssm_codedeploy" {
  role       = data.aws_iam_role.refit_ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy"
}

resource "aws_iam_role_policy_attachment" "refit_ec2_ssm_cloudwatch_agent" {
  role       = data.aws_iam_role.refit_ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "refit_ec2_ssm_cloudwatch_metrics" {
  role       = data.aws_iam_role.refit_ec2_ssm.name
  policy_arn = "arn:aws:iam::${data.aws_caller_identity.prod_v2.account_id}:policy/CloudWatch-Metrics-Write-Policy"
}

# --- 인라인 정책: ECR (refit-* 레포만 pull) ---
resource "aws_iam_role_policy" "refit_ec2_ssm_ecr" {
  name = "${var.name_prefix}-refit-ec2-ssm-ecr"
  role = data.aws_iam_role.refit_ec2_ssm.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
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

# --- 인라인 정책: S3 (CodeDeploy 배포 버킷만) ---
resource "aws_iam_role_policy" "refit_ec2_ssm_s3_deploy" {
  name = "${var.name_prefix}-refit-ec2-ssm-s3-deploy"
  role = data.aws_iam_role.refit_ec2_ssm.name

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
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
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
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}
