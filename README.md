# calculator_IaC_Terra

Terraform repository for the calculator platform on AWS.

Current `dev` scope:
- foundation: VPC, EKS, ECR, GitHub OIDC
- addons: AWS Load Balancer Controller, ArgoCD

## Dev Apply Order

1. Foundation:
   `cd envs/dev && terraform init -reconfigure && terraform plan && terraform apply`
2. Addons:
   `cd envs/dev/addons && terraform init -reconfigure && terraform plan -out tfplan && terraform apply tfplan`

## ArgoCD Access

1. Verify ArgoCD pods:
   `kubectl -n argocd get pods`
2. Get the initial admin password:
   `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo`
3. Start port-forward:
   `kubectl -n argocd port-forward svc/argocd-server 8080:443`
4. Open:
   `https://localhost:8080`
5. Login with:
   username `admin`
   password from the secret above

## Notes

- ArgoCD is intentionally internal in `dev`; it is not exposed by ALB at this stage.
- GitOps application sync from `calculator_desire_state` is the next step after that repo is aligned with the current Source of Truth.
