locals {
  aws_region               = "us-east-1"
  cluster_name             = "calculator-dev"
  argocd_namespace         = "argocd"
  calculator_app_name      = "calculator-dev"
  calculator_namespace     = "calculator"
  calculator_repo_url      = "https://github.com/haimNemir/calculator_desire_state.git"
  calculator_target_branch = "main"
}

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }
}

# Explained in addons/main
data "aws_eks_cluster" "this" {
  name = local.cluster_name
}
# Explained in addons/main
data "aws_eks_cluster_auth" "this" { 
  name = data.aws_eks_cluster.this.name
}

provider "aws" {
  region = local.aws_region
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

resource "kubernetes_manifest" "calculator_dev_application" { # 
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application" # Here we define a special resource of kind "Application" which is used by ArgoCD to manage our cluster applications. Pay attention that this resource is a command to ArgoCD to manage something, and its not the application itself. 
    metadata = {
      name      = local.calculator_app_name # This is the name of the application object.
      namespace = local.argocd_namespace    # In this namespace the apllication "object" will be created, This object is not the app itself, is the object that ArgoCD will use to manage apps, and in our case we will create the app itself in the "calculator" namespace.
    }
    spec = {
      project = "default"
      source = {
        repoURL        = local.calculator_repo_url       # Here we specify the GitHub repository URL where our desired state and Helm chart are located. And ArgoCD will watch this repository for changes and when it detects a change (The change will accure by GitHub CI - he will change the tag name), it will automatically pull from ECR the new image and update the application accordingly. 
        targetRevision = local.calculator_target_branch  # Here we specify the branch of the repository that ArgoCD should monitor for changes and accordingly update the application, here we set it to "main", because changes in others branches are not relevant for our application.
        path           = "charts/calculator" # Here we define the path within the repository where our Helm chart is located. This allows ArgoCD to find the necessary files to deploy our application.
        helm = {
          valueFiles = [
            "../../environments/values-dev.yaml",
            "../../environments/values-dev-images.yaml",
          ]
        }
      }
      destination = { # Tell ArgoCD where to deploy the application "calculator" itself, 
        server    = "https://kubernetes.default.svc" # Here we define in which cluster the application will be deploy. Even the ArgoCD itself already exist in the same cluster, still you need to specify the target cluster because ArgoCD can manage applications outside the cluster he is deployed into. 
        namespace = local.calculator_namespace # Here we tells ArgoCD to install our app inside this namespace.
      }
      syncPolicy = { # Here we define the sync setting of ArgoCD to our git repository, this mean when and how to synchronize the cluster against the git repo.
        automated = { # automated = make the sync automatically. So ArgoCD not only will report that there is a gap between desire state and actual state he is also will close this gap. 
          prune    = true # Allows ArgoCD also controls resource deletion beside of add new resources and manage the exists. Its relevant when in the cluster there is a resource that not longer exist in the desire state. 
          selfHeal = true # If there is a gap between the cluster and the desire state, then ArgoCD will fix it even if this gap accrued by someone who's delete in purpose something through the kub API. 
        }
        syncOptions = [ # Here we adding block that allows add another sync settings.
          "CreateNamespace=true", # If the namespace we define in "destination.namespace" does not exist yet he will create it automatically.
        ]
      }
    }
  }
}
