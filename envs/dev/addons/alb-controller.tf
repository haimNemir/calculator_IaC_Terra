resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.13.4"

  set = [ 
    {
      name  = "clusterName"
      value = data.terraform_remote_state.foundation.outputs.eks_cluster_name
    }
  ]
}

