# calculator_IaC_Terra

Terraform repository for the calculator platform on AWS.

Current `dev` scope:
- foundation: VPC, EKS, ECR, GitHub OIDC
- addons: AWS Load Balancer Controller, ArgoCD
- app layer: ArgoCD `Application` resources that point to `calculator_desire_state`

## Dev Apply Order

1. Foundation:
   `cd envs/dev && terraform init -reconfigure && terraform plan && terraform apply`
2. Addons:
   `cd envs/dev/addons && terraform init -reconfigure && terraform plan -out tfplan && terraform apply tfplan`
3. ArgoCD apps:
   `cd envs/dev/argocd-apps && terraform init -reconfigure && terraform plan && terraform apply`

## Dev Bring-Up Script

For a full bring-up flow after the environment was destroyed, use:
`cd /mnt/c/Users/Haim/Documents/Projects/Calculator/calculator_IaC_Terra/scripts`
`./apply-dev.sh`

What it does:
- applies `envs/dev`
- applies `envs/dev/addons`
- applies `envs/dev/argocd-apps`
- refreshes kubeconfig
- starts a self-restarting ArgoCD port-forward supervisor on `https://localhost:8080`
- waits for the ArgoCD app to become `Synced` and `Healthy`
- opens Brave with both ArgoCD and the public calculator URL
- sends a completion summary email through SNS
- prints the ArgoCD username/password in the local run log

Optional flags for `./apply-dev.sh`:
- `--region <aws-region>` to override the default region
- `--cluster-name <name>` to override the default cluster name
- `--notify-email <address>` to override the default email recipient
- `--port-forward-port <port>` to use a different local ArgoCD port
- `--skip-port-forward` to leave ArgoCD internal only
- `--log-file <path>` to choose a custom log file

## Dev Destroy

For an aggressive teardown flow that prioritizes removing cost-bearing AWS resources and sends a summary email, use:
`cd /mnt/c/Users/Haim/Documents/Projects/Calculator/calculator_IaC_Terra/scripts`  
`nohup ./destroy-dev.sh > /tmp/destroy-dev.out 2>&1 &` # Enter in WSL in PowerShell
`tail -f /tmp/destroy-dev.out`   # Follow the progress log. Safe to stop with Ctrl+C after you see "Destroy run finished with status ...".
OR:
`cd /mnt/c/Users/Haim/Documents/Projects/Calculator/calculator_IaC_Terra/scripts && nohup ./destroy-dev.sh > /tmp/destroy-dev.out 2>&1 & sleep 5 && tail -f /tmp/destroy-dev.out`

What it does:
- destroys `envs/dev/argocd-apps`
- destroys `envs/dev/addons`
- destroys `envs/dev` while preserving `module.ecr`
- retries Terraform destroys after auto-unlocking a stale remote state lock when the lock is older than 15 minutes and no other local Terraform process is running
- removes orphaned load-balancer-controller security groups even if the EKS cluster is already gone
- verifies that foundation state keeps only `module.ecr` entries before reporting success

Optional flags for `./destroy-dev.sh`:
- `--notify-email <address>` to override the default recipient
- `--scope all` to also destroy `bootstrap`
- `--region <aws-region>` and `--cluster-name <name>` if you need non-default values

If the foundation destroy was interrupted and you need to finish it manually while preserving ECR:
1. `cd /mnt/c/Users/Haim/Documents/Projects/Calculator/calculator_IaC_Terra/envs/dev`
2. If Terraform reports `Error acquiring the state lock`, run `terraform force-unlock -force <LOCK_ID>`
3. Run:
   `terraform destroy -target=module.github_oidc -target=module.eks -target=module.vpc`
4. Verify that only `module.ecr` entries remain:
   `terraform state list`

## ArgoCD Access
0. Refresh:
   `aws eks update-kubeconfig --region us-east-1 --name calculator-dev`
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

If you use `scripts/apply-dev.sh`, it now starts a background supervisor that restarts `kubectl port-forward` automatically if the connection drops. Manual `kubectl port-forward` is still fine for short sessions, but it is not intended to be a permanent access method.

## Notes

- ArgoCD is intentionally internal in `dev`; it is not exposed by ALB at this stage.
- For always-on browser access, the proper long-term solution is to publish ArgoCD through a supported ingress or load balancer path instead of relying on `kubectl port-forward`.
- GitOps application sync now happens through the separate `envs/dev/argocd-apps` layer.
- The public calculator app is exposed through the ALB created from the Ingress managed in `calculator_desire_state`.
