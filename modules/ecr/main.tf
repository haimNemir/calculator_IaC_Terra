resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories) # toset- convert list to set to avoid duplicates, in result it looks like this: { "calculator-backend" = "calculator-backend", "calculator-frontend" = "calculator-frontend" }

  name = "calculator-${var.environment}-${each.value}"
  force_delete = var.delete_repo_when_full

  image_scanning_configuration {
    scan_on_push = true # This enables image scanning on push, which helps identify vulnerabilities in the container images as soon as they are pushed to the repository.
  }
}
