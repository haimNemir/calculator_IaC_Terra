resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = local.alb_controller_namespace
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.14.0"

  set = [ # Define the values that we want to set for the ALB controller Helm chart, and we will use these values to configure the ALB controller to work with our EKS cluster and with the IRSA that we created for it.
    {
      name  = "clusterName"
      value = data.aws_eks_cluster.this.name
    },

    {
      name  = "region"
      value = local.aws_region
    },

    {
      name  = "vpcId"
      value = data.aws_eks_cluster.this.vpc_config[0].vpc_id # vpc_config list - contains only one object, so we can access it with [0], inside this object we have: vpc_id, subnets_ids[...], security_group_ids[...], and so we access the vpc_id to tell the ALB controller in which VPC it should create the load balancers. 
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
