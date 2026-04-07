# -----------------------------------------------------
# IAM (refit prod v3 - self-managed K8s)
# EC2 인스턴스용 IAM 역할: SSM, ECR, CloudWatch, CodeDeploy, S3
# -----------------------------------------------------

data "aws_caller_identity" "current" {}

# ------- IAM Role -------
resource "aws_iam_role" "ec2_ssm" {
  name = "RefitEC2SSMRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = { Name = "RefitEC2SSMRole" }
}

# ------- Managed Policy Attachments -------
locals {
  ec2_managed_policies = [
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonEC2RoleforAWSCodeDeploy",
    "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess",
    "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",
    "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole",
  ]
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  for_each   = toset(local.ec2_managed_policies)
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = each.value
}

# ------- Inline Policy: ECR Auth -------
resource "aws_iam_role_policy" "ecr_auth" {
  name = "refit-prod-v2-refit-ec2-ssm-ecr"
  role = aws_iam_role.ec2_ssm.id

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
          "ecr:BatchCheckLayerAvailability",
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/refit-*"
      }
    ]
  })
}

# ------- Inline Policy: S3 Deploy Bucket -------
resource "aws_iam_role_policy" "s3_deploy" {
  name = "refit-prod-v2-refit-ec2-ssm-s3-deploy"
  role = aws_iam_role.ec2_ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::refit-prod-v2-deployments",
          "arn:aws:s3:::refit-prod-v2-deployments/*",
        ]
      }
    ]
  })
}

# ------- Instance Profile -------
resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "RefitEC2SSMProfile"
  role = aws_iam_role.ec2_ssm.name

  tags = { Name = "RefitEC2SSMProfile" }
}
