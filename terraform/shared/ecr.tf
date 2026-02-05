# -----------------------------------------------------
# ECR Repositories
# -----------------------------------------------------

resource "aws_ecr_repository" "services" {
  for_each = toset(var.ecr_services)

  name                 = "${var.project_name}-${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name    = "${var.project_name}-${each.key}-ecr"
    Service = each.key
  }
}

# -----------------------------------------------------
# ECR Lifecycle Policies
# -----------------------------------------------------

resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = toset(var.ecr_services)
  repository = aws_ecr_repository.services[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.ecr_image_retention_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.ecr_image_retention_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
