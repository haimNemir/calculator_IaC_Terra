# You will find explenation inside the README file in the same directory.

# Here we are fetching the foundation state file (envs/dev/backend), which is stored in S3, but we can later fetch only the outputs from the state file. We will use these outputs to configure our providers and to deploy our addons on the EKS cluster that was created in the foundation layer.
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
  required_version = ">= 1.5.0" # required_version of terraform.

  # required_providers - Ask from terraform to download the providers.
  required_providers { # Here we are defining the providers that we will use in this module.    Only with those providers we can define resources such as aws_eks_cluster, kubernetes_namespace, because Terraform doesn't know how to speak to AWS or Kubernetes without the providers. And those providers convert the Terraform code requests into API of those platforms as a regular requests.
    aws = {            # We use AWS provider to create resources on AWS, such as EKS cluster, VPC, etc.
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    kubernetes = { # We use Kubernetes provider to create resources on the cluster (AWS provider can't do that), such as namespaces, deployments, etc. And the main porpuse of this provider is to deploy specific resources on the cluster.
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }

    helm = { # We use Helm provider to deploy Helm charts on the cluster, such as AWS Load Balancer Controller, ArgoCD, Prometheus, ExternalDNS. And the kubernetes provider can't do that, because it's only for deploying specific resources, and Helm charts are a collection of resources that are defined in a specific way, and the Helm provider knows how to deploy them on the cluster.
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}

# To understand what we are doing here, you need to understand that even though we (local Terraform) have permissions to access AWS API and create resources such as EKS cluster, still we need to get a token that holds the credentials to get access to the cluster himself. And that's what we are doing here, we ask from AWS to give us a token that we can use to access the cluster, and we are using the outputs from the foundation state file to get the cluster name, which is required to get the token.
data "aws_eks_cluster_auth" "this" {                                     # Here we are getting token to access the cluster.
  name = data.terraform_remote_state.foundation.outputs.eks_cluster_name # The cluster name that we create in the foundation layer - its nessecary to get token with the name of the cluster we want to access.
}

provider "aws" {
  region = data.terraform_remote_state.foundation.outputs.region
}

# Here we are defining the kubernetes provider, which is required to access the cluster and deploy resources on it. We need him in addition to the AWS provider, because AWS provider is only for creating resources on AWS.  
provider "kubernetes" {                                                                            # Here we define how to access from our local kubernetes provider to the API Server of the cluster.
  host                   = data.terraform_remote_state.foundation.outputs.eks_cluster_endpoint     # Here we define the host of the API Server of the cluster, which is required to access to the correct cluster.
  cluster_ca_certificate = base64decode(data.terraform_remote_state.foundation.outputs.cluster_ca) # CA is a certificate authority that proves the identity of the cluster, without it we can't be sure that the target we are trying to access is the correct target, it's always can be "Man in the middle" attack. And with this CA we can be sure that we are accessing the correct target (the cluster), and not some fake cluster that someone created to steal our credentials. We need to decode it because it's encoded in base64 format, and we need to decode it to get the actual certificate.
  token                  = data.aws_eks_cluster_auth.this.token                                    # We are using the token that we got from AWS above (data "aws_eks_cluster_auth" "this") to access to the cluster.
}

# With this Helm provider we are defining on the cluster of kubernetes some charts, and to do that we need to get access to the cluster, and that's is what we are doing here - we provide the certificate of access to the cluster to the helm provider, as we did with the kubernetes provider above.
provider "helm" {
  kubernetes = {
    host                   = data.terraform_remote_state.foundation.outputs.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.foundation.outputs.cluster_ca)
    token                  = data.aws_eks_cluster_auth.this.token # We are using the token that we got from AWS above (data "aws_eks_cluster_auth" "this") to access to the cluster
  }
}
