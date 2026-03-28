Addons:
In general when we using this term "addons" we means to address a plug-in's in the cluster in AWS. We can use those addons by using helm-charts.
Here we use those addons:

A: Application Load Balancer.
Here we want be able to route requests between our pods in the cluster depends on the load of the app, And for this we need the AlB. To get this we will add to our cluster the currect addons, This addons is creating a controller with the name of "AWS Load Balancer Controller". And he will run inside a pod inside the cluster. 
This controller will search for ingress resources inside the Controle Plane of the cluster (in etcd), And when he will find one - he will create an ALB Service of AWS and this ALB will connect to the ingress resources inside the cluster.
In result the ALB will get the routing rules from the ingress resource inside the controle plane, and according to those rules the requests will be navigate to the correct destination. 

But before all of this happend, the pod of this Controller need to get permissions to those staff:
A- Access to AWS API, to send the command of creating the service (ALB).
B- Create an AWS Service (ALB).
C- Get access to the kubernetes cluster to watch on ingress resources. 

Here a quick explanation how its work:
To give to the pod permissions to Kubernetes - kubernetes give him a JWT token, and with this token he will get a Service Account, and the permissions (RBAC) is binding with Role Binding to this Service Account.
To give him permissions to AWS API - the token that he got from kubernetes holds an annotations that allows the Service Account he use - to get permissions of IAM Role that allows to create resources (ALB) in AWS. 

Here a full explanation how its works-
Terms:
 
1 - RBAC (Role Based Access Control) - This is set of rules of kubernetes that determine for whom that hold it what he can do in the cluster like delete resources or watch some resources like ingress. Those rules connected to ServiceAccount (see "ServiceAccount" below) by Role Binding.
2 - Role Binding: Is definition that connect between ServiceAccount and RBAC rules.
3 - Service Account: This is a general identity inside Kubernetes. And each pod in his creation will be associated with some ServiceAccount by kubernetes.
This ServiceAccount associate with IAM Role (By IRSA) to grant permissions in AWS for whom is hold it (-Pods). 
ServiceAccount will create automatically by kubernetes inside each namespace and he will get the name of "default". And also you can menually in terraform create an unique ServiceAccount. Or Helm-chart can create also an unique service account. 
In our addon the pod that holds the ALB Controller will get a unique ServiceAccount with IAM Role perrmisions to change resources in AWS. 
4 - IRSA- (IAM Role for Service Account): This is what that connect between IAM Role to Service account. If in the IAM Role there is rule that allows for who that hold him to create resources in AWS - So for this Service Account it will be permited.
5 - OIDC (Open ID Connect) Provider: Is a mechanism that helps AWS verified tokens that created by kubernetes or other providers. 
It's can be defined in the console in IAM/add identity provider/open ID connect, or with terraform or helm chart.
And is grant to kubernetes the permissions to create tokens that AWS will trust on.
In this definition we need to define the trusted inentity that authorized to create tokens with access to AWS resources (the cluster), and the audience (The receiver - AWS).
After you will create this mechanism, AWS will remember the cluster as a trusted identity by create a pair of public and private keys - The cluster will receive the private key and aws will keep the public key, and when kubernetes will create a token for pod he will write inside it a credentials using his private key so when AWS will receive this token he will identify the provider of this token as our cluster only if the private key matches the public key.

6 - JWT Token provided by kubernetes when pod created. This allows pod to verify his identity (authentication) with the API controle plane of the cluster, And also with anothers external identities such as AWS.
This token signing by kubernetes with a private credentials.
Its holds this information:
  - provider of this token (kubernetes).
  - the audience(receiver) of this token (sts.amazonaws.com).
  - the expiration time of the token.
  - the name of the ServiceAccount + the accessible namespace for this pod.


How the pod with the ALB Controller can get permission to do changes in AWS?
Answer: When the pod try to connect to the AWS API he will give his JWT Token that got from kubernetes. 
sts of AWS will check if the provider of this token approved by check if the provider includes as OIDC Provider, and if so the token will be approved.
in this JWT there is an annotation that determain which IAM Role connect to this JWT (by IRSA) and when the pod presents the JWT Token - AWS API give him in return temperory credentials that allows make changes in the AWS Resources.



Service Linked Role:
This "ServiceLinkedRole" is role in IAM that allows AWS Services (Here is the ALB Controller) to get permissions to do changes in another services in AWS.
This role can create only for one AWS Service.
In our case the service that got this role is the ALB and he need it to makes changes in the cluster.


B: ArgoCD.
ArgoCD is installed in the `argocd` namespace by Helm and stays internal in `dev`.
For the current project stage we keep the ArgoCD server as `ClusterIP` and access it with `kubectl port-forward`, because the Final Project requires documented access but does not require a public ALB in front of ArgoCD.

Terraform files:
- `argocd.tf`
- `argocd-values.yaml`

Quick access flow:
1. Apply the addons layer:
   `cd envs/dev/addons && terraform init -reconfigure && terraform plan -out tfplan && terraform apply tfplan`
2. Verify pods:
   `kubectl -n argocd get pods`
3. Get the initial admin password:
   `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo`
4. Start local access:
   `kubectl -n argocd port-forward svc/argocd-server 8080:443`
5. Open:
   `https://localhost:8080`
6. Login:
   username `admin`
   password from step 3

Optional CLI login:
`argocd login localhost:8080 --username admin --password <PASSWORD> --insecure`

Current scope note:
ArgoCD installation and access are implemented here.
The ArgoCD `Application` sync to `calculator_desire_state` is implemented in the separate `envs/dev/argocd-apps` layer, after the required CRDs are installed here.

