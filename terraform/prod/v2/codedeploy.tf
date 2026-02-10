# -----------------------------------------------------
# CodeDeploy + S3 bucket for deployments (refit-prod-v2)
# -----------------------------------------------------

resource "aws_s3_bucket" "prod_v2_deployments" {
  bucket = "${replace(local.name, ".", "-")}-deployments"

  tags = {
    Name = "${local.name}-deployments"
    tier = local.tier_deploy
  }
}

resource "aws_s3_bucket_versioning" "prod_v2_deployments" {
  bucket = aws_s3_bucket.prod_v2_deployments.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_codedeploy_app" "prod_v2_backend" {
  name             = "${local.name}-backend"
  compute_platform = "Server"

  tags = {
    Name = "${local.name}-backend"
    tier = local.tier_deploy
  }
}

resource "aws_codedeploy_deployment_group" "prod_v2_backend" {
  app_name              = aws_codedeploy_app.prod_v2_backend.name
  deployment_group_name = "${local.name}-backend-dg"
  service_role_arn      = aws_iam_role.prod_v2_codedeploy.arn

  deployment_config_name = "CodeDeployDefault.OneAtATime"

  ec2_tag_set {
    ec2_tag_filter {
      key   = "tier"
      type  = "KEY_AND_VALUE"
      value = local.tier_backend
    }
  }

  deployment_style {
    deployment_type   = "IN_PLACE"
    deployment_option = "WITHOUT_TRAFFIC_CONTROL"
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  tags = {
    Name = "${local.name}-backend-dg"
    tier = local.tier_deploy
  }
}
