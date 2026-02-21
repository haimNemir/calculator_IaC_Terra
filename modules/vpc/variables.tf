variable "name" {
  type        = string
  description = "Prefix/name for VPC resources"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for public subnets (one per AZ)"
}

variable "azs" {
  type        = list(string)
  description = "List of availability zones to use"
}

variable "eks_cluster_name" {
  type        = string
  description = "Optional: EKS cluster name for subnet tagging"
  default     = null
}