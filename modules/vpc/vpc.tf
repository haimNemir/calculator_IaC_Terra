resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # This is allows for our VPC to get a DNS resolver, Even this is a default value in AWS (And also "enable_dns_hostnames") so you will think its not nessecery but because its very important we define it explicitly. You must to understand that there is a DNS resolver inside each VPC you create, this resolver created by AWS and he's responsible to convert IPs to DNS and vice versa from the VPC to the net and inside the VPC itself. If he will not exist it will be impossible for server backend to understand how is it frontend.
  enable_dns_hostnames = true # This allows for our VPC to assign DNS hostnames to EC2 instances with public IPs, from 192.168.10.100 to "backend", And its important because that EKS cluster will use this feature to assign hostnames to the nodes in the cluster.

  tags = {
    Name = "${var.name}-vpc"
  }
}
