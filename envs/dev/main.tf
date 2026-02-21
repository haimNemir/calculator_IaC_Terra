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

  eks_cluster_name = "calculator-dev"
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

module "eks" {
  source = "../../modules/eks"

  cluster_name = "calculator-dev"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  node_instance_types = ["t3.medium"]
  node_min_size       = 1
  node_desired_size   = 1
  node_max_size       = 2
}