resource "aws_ecr_repository" "portal" {
  name                 = "${var.name_prefix}-portal-${var.resource_suffix}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-portal-${var.resource_suffix}-repo"
  })
}

resource "aws_ecr_lifecycle_policy" "portal" {
  repository = aws_ecr_repository.portal.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "portal" {
  name              = "/aws/eks/${var.cluster_name}-${var.resource_suffix}/portal"
  retention_in_days = 7

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-${var.resource_suffix}-portal-logs"
  })
}

output "ecr_repository_url" {
  value = aws_ecr_repository.portal.repository_url
}

output "ecr_repository_name" {
  value = aws_ecr_repository.portal.name
}

output "cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.portal.name
}
