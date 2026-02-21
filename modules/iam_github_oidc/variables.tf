variable "github_owner" { # The owner of the GitHub account.
  type        = string
  description = "GitHub org/user name"
}

variable "github_repo" { # The name of the GitHub repository, To give a minimal permission to GitHub Actions, only to this repo.
  type        = string
  description = "GitHub repository name"
}

variable "role_name" {
  type        = string
  description = "IAM role name for GitHub Actions OIDC"
}

variable "ecr_repository_arns" {
  type        = list(string)
  description = "List of ECR repository ARNs that GitHub Actions can push to"
}
