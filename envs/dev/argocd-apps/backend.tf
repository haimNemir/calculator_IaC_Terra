terraform { 
  backend "s3" {
    bucket         = "calculator-tfstate-haim-nemir"
    key            = "calculator/dev/argocd-apps/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "calculator-terraform-locks"
    encrypt        = true
  }
}
