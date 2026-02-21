terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}


module "vpc" {
  source = "../../modules/vpc"

  name                = "calculator-dev"
  vpc_cidr            = "10.10.0.0/16"
  public_subnet_cidrs = ["10.10.1.0/24", "10.10.2.0/24"]
  azs                 = ["us-east-1a", "us-east-1b"]
}

module "ecr" {
  source      = "../../modules/ecr"
  environment = "dev"
  repositories = [
    "backend",
    "frontend",
  ]
}
module "github_oidc" {
  source = "../../modules/iam_github_oidc"

  github_owner = "haimNemir"
  github_repo  = "calculator"
  role_name    = "calculator-github-actions-dev"

  ecr_repository_arns = values(module.ecr.repository_arns)
}
