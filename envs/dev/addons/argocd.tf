locals {
  argocd_namespace = "argocd"
}
# Create a namespace for ArgoCD.
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = local.argocd_namespace
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = local.argocd_namespace
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.2.3"

  create_namespace = false                                       # Here we decide not to let Helm create the namespace, and we are creating it ourselves above in the - resource "kubernetes_namespace_v1". The reason for this is that we want to have more control over the namespace creation, because in this way whan we perform a terraform destroy, the namespace will be deleted and all the resources in it will be deleted as well. And if we let Helm create the namespace and perform a terraform destroy the namespace will not be deleted.
  values           = [file("${path.module}/argocd-values.yaml")] # Here we are passing the values file to the Helm release, this file contains the configuration for ArgoCD.
  timeout          = 600

  depends_on = [
    kubernetes_namespace_v1.argocd # We ensure that the namespace is created before we try to install ArgoCD - its nesessary.
  ]
}
