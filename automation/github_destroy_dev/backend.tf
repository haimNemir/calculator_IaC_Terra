terraform {
  backend "s3" {
    bucket         = "calculator-tfstate-haim-nemir"
    key            = "automation/github-destroy-dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "calculator-terraform-locks"
    encrypt        = true
  }
}
