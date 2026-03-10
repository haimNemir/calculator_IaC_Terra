resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = local.alb_controller_namespace
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.14.0"

  set = [ # Define the values that we want to set for the ALB controller Helm chart, and we will use these values to configure the ALB controller to work with our EKS cluster and with the IRSA that we created for it.
    {
      name  = "clusterName"
      value = data.terraform_remote_state.foundation.outputs.eks_cluster_name
    },

    {
      name  = "region"
      value = data.terraform_remote_state.foundation.outputs.region
    },

    {
      name  = "vpcId"
      value = data.terraform_remote_state.foundation.outputs.vpc_id
    },

    # We pre-create the service account with IRSA, so we tell Helm- do not create the service account.
    {
      name  = "serviceAccount.create"
      value = "false"
    },

    { # Here we tell Helm to use the service account that we created for the ALB controller.
      name  = "serviceAccount.name"
      value = local.alb_controller_sa_name
    }
  ]
  depends_on = [ # Make sure that the ALB controller is deployed only after the IAM Role and the Service Account are created, because the ALB controller needs the IAM Role to work, and the Service Account to be able to assume this role.
    aws_iam_role_policy_attachment.alb_controller,
    kubernetes_service_account_v1.alb_controller
  ]
}
