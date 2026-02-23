variable "repositories" {
  type        = list(string)
  description = "List of ECR repository names to create"
}

variable "environment" {
  type        = string
  description = "Environment name (dev/stage/prod)"
}

variable "delete_repo_when_full" {
  type = bool
  description = "Its will force delete to the repositories even there are a images stored inside"
}