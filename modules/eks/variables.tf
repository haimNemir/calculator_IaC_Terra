variable "cluster_name" {
  type        = string
  description = "EKS cluster name"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where EKS will be deployed"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets for EKS (for Dev we use public subnets)"
}

variable "node_instance_types" {
  type        = list(string)
  description = "Node group instance types"
  default     = ["t3.medium"]
}

variable "node_min_size" {
  type        = number
  description = "Node group min size"
  default     = 1
}

variable "node_desired_size" {
  type        = number
  description = "Node group desired size"
  default     = 1
}

variable "node_max_size" {
  type        = number
  description = "Node group max size"
  default     = 2
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes version"
  default     = "1.34"
}

variable "endpoint_public_access" {
  type        = bool
  description = "Enable public access to the EKS API endpoint"
  default     = true
}

variable "endpoint_private_access" {
  type        = bool
  description = "Enable private access to the EKS API endpoint"
  default     = true
}

variable "public_access_cidrs" {
  type        = list(string)
  description = "Allowed CIDRs for the public EKS API endpoint"
  default     = ["0.0.0.0/0"]
}

variable "admin_principal_arn" {
  type        = string
  description = "IAM principal ARN to grant EKS Cluster Admin access"
}

variable "environment" {
  type        = string
  description = "Environment name (dev/stage/prod)"
}

variable "project_name" {
  type        = string
  description = "Current project name for tags in AWS"
}

variable "addons" {
  description = "EKS managed addons to install for the cluster"
  # Syntax of map is: map(type) and initial with values of "key = value", like "map(string)" and then the 
  # Syntax of object is: "object({name = string \n age = number})" and you must enter inside of new each instance those variables from those types.
  # Syntax of optional is:  ... = optional(type, default value). And this function (optional) is basically makes this variable inside the object net necessary so if you will not define his value - he will make this value as "null", And if there is a default value to this variable then the value will be the default value and when you will explicitly define his value it must to be matched with the value type of this variable. 
  # Here when we do this: map(object{...})   -  this mean that we create here a teplate for variable from type of map (contain key/value pair), and his key/value will be the "object name" (key) + the "object values" (what inside the kurly brackets). So when we want to inintial instance from this variable like inside env/dev/main/ inside block of module "eks" - we will need to to this in this syntax, so it will look like this: addon (key of map) = {...}(what inside the curly brackets is the value of map). 
  type = map(object({
    name                        = optional(string) # optional: is a variable with the format of (type, default)
    before_compute              = optional(bool, false)
    most_recent                 = optional(bool, true)
    addon_version               = optional(string)
    configuration_values        = optional(string)
    preserve                    = optional(bool, true)
    resolve_conflicts_on_create = optional(string, "NONE")
    resolve_conflicts_on_update = optional(string, "OVERWRITE")
  }))
  default = null
}
