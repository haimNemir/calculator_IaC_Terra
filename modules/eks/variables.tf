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
  type = map(object({ # In two words - we create here a template like "Class" in java, and in the modules we will create "objects" from this "Class".
    # optional: is a variable with the format of (type, default)
    name                        = optional(string)                # Name of the addon.
    before_compute              = optional(bool, false)           # If true, the addon will be created before the creation of the nodes.
    most_recent                 = optional(bool, true)            # If true, the most recent version of the addon will be used.
    addon_version               = optional(string)                # Version of the addon to use. If not specified, the most recent version will be used.
    configuration_values        = optional(string)                # A JSON string that contains a specific configuration values for the addon.
    preserve                    = optional(bool, true)            # If true, the addon will not be deleted when the cluster is deleted or in other scenarios like this.
    resolve_conflicts_on_create = optional(string, "NONE")        # Determines how to behave when there is a conflict during addon creation. For example, if an addon with the same name already exists - what to do? "OVERRIDE" - means to override the existing addon, "NONE" - means to do nothing and keep the existing and stop "terraform apply" , "DELETE" - means to delete the existing addon and create a new one. 
    resolve_conflicts_on_update = optional(string, "OVERWRITE")   # If we decided to update the addon to a new version.
  }))
  default = null
}
