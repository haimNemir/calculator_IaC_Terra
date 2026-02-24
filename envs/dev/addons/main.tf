data "terraform_remote_state" "foundation" {
  backend = "s3"

  config = {
    bucket         = "calculator-tfstate-haim-nemir"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "calculator-terraform-locks"
    encrypt        = true
  }
}

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}


provider "aws" {
  region = data.terraform_remote_state.foundation.outputs.region
}


data "aws_eks_cluster_auth" "this" {
  name = data.terraform_remote_state.foundation.outputs.eks_cluster_name
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.foundation.outputs.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.foundation.outputs.cluster_ca)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.foundation.outputs.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.foundation.outputs.cluster_ca)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}