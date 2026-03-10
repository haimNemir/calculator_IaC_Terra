terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
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
  delete_repo_when_full = true
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

  cluster_name       = "calculator-dev"
  kubernetes_version = "1.33"

  # See modules/eks/variables/ variable "addons" notes to understand this syntax below.
  addons = { # Define the variable "addons", His from type map(object{}). the key/value pairs of map is the -   coredns(key) = {}(value), kube-proxy(key) = {}(value). And inside each value of this map we need define object (like class in java) with parameters but you don't have to define those parameters because they from type of optional, there for the object of "coredns" is empty because all of his parameters are not define here. And the object of "vpc-cni" is a object that we define a unique values for him.
    # Here we define addons on the eks module. Those addons called "EKS Managed Addons" and by default managed by AWS and by explicitly mentions those here we turn them to our menual contole. Those addons diffrent from the ALB addon, because those addons are part from the eks and must be exist in eks, and ALB addon is a open-source helm-chart and he is layer above kubernetes this mean that only after the kubernetes work - on top of it we install ALB addon to connect to ingress inside the cluster.
    coredns    = {}         # This addon coreDNS - is the DNS Server of kubernetes and he convert IP to DNS name for the resources of the kubernetes. We keep him empty because we want to save the default values of the variable we define in variables file.
    kube-proxy = {}         # This addon kube-proxy run on pods inside each node of the cluster, and he is responsible to route traffic from services like "back-end service" to his pods. 
    vpc-cni = {             # This addon vpc-cni (CNI = Container Network Interface) - His responsibility is to give IPs for each pod(!) inside each node from the scope of the same subnet as his node. And this is allow for each pod to communicate with AWS services and with RDS ect. 
      before_compute = true # Here we decide that this addon must be installed before the compute of the node-groups - because its necessary for him to work correctly.
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  node_instance_types = ["t3.medium"]
  node_min_size       = 1
  node_desired_size   = 1
  node_max_size       = 2

  endpoint_public_access  = true
  endpoint_private_access = true
  public_access_cidrs     = ["0.0.0.0/0"]

  admin_principal_arn = "arn:aws:iam::757630643687:user/localadmin"

  environment  = "dev"
  project_name = "calculator"

}

data "aws_region" "current" {}
