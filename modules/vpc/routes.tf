resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0" # Open rount from inside the VPC to the Internet. And using the IGW of the VPC as the target for this route.
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name}-public-rt"
  }
}

resource "aws_route_table_association" "public" { # Associating this route table with the public subnets. This will ensure that the public subnets can access the Internet through the IGW.
  count          = length(aws_subnet.public)      #  Its look like that we have only one resource of aws_subnet.public, but in fact we have as many resources as the length of the public_subnet_cidrs list.
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
