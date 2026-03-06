module "eks" {
  source  = "terraform-aws-modules/eks/aws" # Here we import EKS module from this URL, This module include a bunch of resources such as Roles, Policies, Sequrity groups, NodeGroup etc..  , Its save as time to define the basic of the EKS resources.
  version = "~> 21.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = var.vpc_id     # Here we define in witch VPC this EKS will be deployed
  subnet_ids = var.subnet_ids # A list of subnets this cluster will use.

  cluster_endpoint_public_access       = var.endpoint_public_access  # Allow access to cluster "API Server" from world network.
  cluster_endpoint_private_access      = var.endpoint_private_access # Allow access also from inside the cluster.
  cluster_endpoint_public_access_cidrs = var.public_access_cidrs     # Here we define from which network cidr can get access to our API Server (if the var 'cluster_endpoint_public_access' is true), In a real app you should include a list of yours IPs like your work place address (192.168.10.100/24) or use a VPN. And if its value like here is [0.0.0.0/0] its include the whole world. 

  enable_irsa = true # irsa = "IAM Roles for Service Accounts". This option when its true is enable to pods in our cluster to get access to another AWS Services such as S3, SecretManager, Route53 etc. By getting IAM role that open the access to another AWS services. The way its give access is by creating OIDC Provider that give Tokens to each new pode that created, with the permissions we define in IAM role.

  access_entries = { # In this block we give full permissions on the k8s cluster to the IAM User that our CLI using.
    admin = {
      principal_arn = var.admin_principal_arn # Here we define who is it the user that get the full access to our k8s cluster - the user is our local CLI.

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" # This policy give full access to maintain our kubernetes cluster, such as create/delete namespaces, apply ingress.
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  eks_managed_node_groups = {
    default = {
      name           = "${var.cluster_name}-mng"
      instance_types = var.node_instance_types
      min_size       = var.node_min_size
      desired_size   = var.node_desired_size
      max_size       = var.node_max_size
      disk_size      = 20
    }
  }

  tags = { # Here we defined a tag name. This tag will added to almost any new resources in the eks. This will help in the future when you will want to manage only the resources with this tag of the project or env. 
    Project     = var.project_name
    Environment = var.environment
  }
}
