variable "repositories" {
  type        = list(string)
  description = "List of ECR repository names to create"
}

variable "environment" {
  type        = string
  description = "Environment name (dev/stage/prod)"
}