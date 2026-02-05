# -----------------------------------------------------
# ECR Outputs
# -----------------------------------------------------

output "ecr_repository_urls" {
  description = "ECR repository URLs for each service"
  value = {
    for service, repo in aws_ecr_repository.services :
    service => repo.repository_url
  }
}

output "ecr_repository_arns" {
  description = "ECR repository ARNs for each service"
  value = {
    for service, repo in aws_ecr_repository.services :
    service => repo.arn
  }
}

output "ecr_repository_names" {
  description = "ECR repository names for each service"
  value = {
    for service, repo in aws_ecr_repository.services :
    service => repo.name
  }
}
