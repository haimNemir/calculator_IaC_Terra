output "repository_urls" {
  value = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}

output "repository_arns" { # Gets the ARNs of our repos in AWS, 
  value = { for k, r in aws_ecr_repository.this : k => r.arn }
}