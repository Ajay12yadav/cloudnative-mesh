############################################################
# ECR MODULE: private Docker registries for our images
############################################################

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)

  name                 = "${var.name}/${each.key}"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true # scan every pushed image for known CVEs
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, { Project = "CloudNative-Mesh", ManagedBy = "Terraform" })
}

# Registries grow forever and storage costs money: keep only the newest images.
resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the newest ${var.keep_last} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.keep_last
      }
      action = { type = "expire" }
    }]
  })
}
