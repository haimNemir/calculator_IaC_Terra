Addons:
In general whan we using this term we mean to address a plug-in's in the cluster in AWS. We can use those addons by using helm-charts.
Here we use those addons:

1- Application Load Balancer.
We want to be able route requests between our pods in the cluster, And for this we 
are creating a controller with the name of "AWS Load Balancer Controller". And he 
will run on pod inside the cluster. 
This controller will search for ingress resources inside the Controle Plane, And when he will find someone he will create a ALB Service of AWS and this ALB will connect to the ingress resources inside the cluster.
So the ALB will get the routing rules from the ingress resource inside the controle plane.
But before this happend the pod of this Controller need to get permissions to create an AWS Service (ALB) and access to AWS API to send the command of create the service. We give him the permissions by defining IRSA (IAM Role for Service Account) on his 
ServiceAccount.
What is Service Account?
Service Account is the ID of each pod inside the cluster.
This ID hold all the permissions of this pod, and it's including:
1 - JWT Token provided by kubernetes that allows pods basic access to the API controle plane of the cluster.
2 - RBAC (Role Based Access Control) - This is set of rules of k8s that define for each one in the cluster - for what he can get access inside the cluster, and how much can he change, and for which namespace. 



  









  In this addon module, we will create a pod that hold a controller inside the EKS cluster in AWS. The controller name is  and his porpuse is to create a ALB (Application Load Balancer) for each resource from type of ingress that he will find in the cluster. In result we will have a ALB connected to each ingress. 
