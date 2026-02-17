terraform { # Here we are defining where we will store our Terraform state file.
  backend "s3" {
    bucket         = "calculator-tfstate-haim-nemir"
    key            = "dev/terraform.tfstate" # key is the path within the bucket where the state file will be stored
    region         = "us-east-1"
    dynamodb_table = "calculator-terraform-locks"
    encrypt        = true
  }
}
