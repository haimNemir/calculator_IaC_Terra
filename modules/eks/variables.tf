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
