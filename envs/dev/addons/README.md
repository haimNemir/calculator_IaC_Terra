Addons:
In general whan we using this term we means to address a plug-in's in the cluster in AWS. We can use those addons by using helm-charts.
Here we use those addons:

A: Application Load Balancer.
Here we want be able to route requests between our pods in the cluster depend on the load, And for this we need the AlB. To get this we will add to out cluster the currect addons, This addons is creating a controller with the name of "AWS Load Balancer Controller". And he will run on pod inside the cluster. 
This controller will search for ingress resources inside the Controle Plane of the cluster, And when he will find some - he will create a ALB Service of AWS and this ALB will connect to the ingress resources inside the cluster.
In result the ALB will get the routing rules from the ingress resource inside the controle plane,and according to those rules the requests will be navigate to the destination. 

But before this happend the pod of this Controller need to get permissions to create an AWS Service (ALB) and access to AWS API to send the command of creating the service, and get access to the kubernetes cluster to watch on ingress resources. 

Here a quick explanation how its work:
To give him permissions to Kubernetes - kubernetes give him a JWT token, and with this token he will get a Service Account, and the permissions (RBAC) is binding with Role Binding to this Service Account.
To give him permissions to AWS API - the token that he got from kubernetes holds an annotations that allows the Service Account he use - to get permissions of IAM Role that allows to create resources (ALB) in AWS. 

Here a full explanation how its work:
1 - JWT Token provided by kubernetes when pod created. This allow pod to verify his identity (authentication) with the API controle plane of the cluster. its holds this information:
  - provider of this token (kubernetes).
  - the audience(receiver) of this token (sts.amazonaws.com).
  - the expiration time of the token.
  - the name of the ServiceAccount + the accessible namespace for this pod. 
2 - RBAC (Role Based Access Control) - This is set of rules of kubernetes that determine for whom that hold it - what he can do in the cluster like delete resources or watch some resources like ingress. Those rules connected to ServiceAccount by Role Binding.
3 - Role Binding: Is definition that connect between ServiceAccount and RBAC rules.
4 - Service Account: In default each pod get a Service Account from type of "default". If you did binding between RBAC Rules and this Account Service - this pod when he access to API Server of kuberentes the API will check his JWT and according to this he will know which Service Account this pod hold, and by this he will know how much permissions this pod need to hold.
5 - IRSA- (IAM Role for Service Account): This is what that connect between IAM Role to Service account. If in the IAM Role there is rule that allows for who that hold him to create resources in AWS - So for this Service Account it will be permited.

How the pod with the ALB Controller can get permission to do this in AWS?
Answer: When the pod try to connect to the AWS API he will give his JWT Token.
in this JWT there is an annotation that determain which IAM Role connect to this JWT (by IRSA) and when the pod presents the JWT Token - AWS API give him in return temperory credentials that allows make changes in the AWS Resources.



  









  In this addon module, we will create a pod that hold a controller inside the EKS cluster in AWS. The controller name is  and his porpuse is to create a ALB (Application Load Balancer) for each resource from type of ingress that he will find in the cluster. In result we will have a ALB connected to each ingress. 
