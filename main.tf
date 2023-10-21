provider "aws" {
  profile = "default"
  region  = var.aws_region
}

# S3 bucket to store terraform state file
resource "aws_s3_bucket" "s3_bucket" {
  bucket = "sum-s3-demo" 
}

#Dynamo DB to lock state file
resource "aws_dynamodb_table" "terraform_lock" {
  name           = "terraform-lock"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# Create vpc1: VPC-A

resource "aws_vpc" "vpc-a" {
  cidr_block       = var.vpc_cidr1
  instance_tenancy = "default"

  tags = {
    Name = "vpc_a"
  }
}

# Create vpc2: VPC-B

resource "aws_vpc" "vpc-b" {
  cidr_block       = var.vpc_cidr2
  instance_tenancy = "default"

  tags = {
    Name = "vpc_b"
  }
}

# Create Subnets for vpc1:VPC-A

resource "aws_subnet" "web1" {
  vpc_id                  = aws_vpc.a.id
  cidr_block              = "10.20.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "web-prod"
  }
}

resource "aws_subnet" "app1" {
  vpc_id     = aws_vpc.a.id
  cidr_block = "10.20.2.0/24"

  tags = {
    Name = "app1"
  }
}

resource "aws_subnet" "app2" {
  vpc_id     = aws_vpc.a.id
  cidr_block = "10.20.3.0/24"

  tags = {
    Name = "app2"
  }
}

resource "aws_subnet" "DB1" {
  vpc_id     = aws_vpc.a.id
  cidr_block = "10.20.4.0/24"

  tags = {
    Name = "DB-vpc-a"
  }
}

resource "aws_subnet" "DBCache" {
  vpc_id     = aws_vpc.a.id
  cidr_block = "10.20.5.0/24"

  tags = {
    Name = "DBCache"
  }
}

# Create Subnets for vpc2:VPC-B

resource "aws_subnet" "web2" {
  vpc_id                  = aws_vpc.b.id
  cidr_block              = "11.20.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "web-vpc-b"
  }
}

resource "aws_subnet" "DB2" {
  vpc_id     = aws_vpc.b.id
  cidr_block = "11.20.4.0/24"

  tags = {
    Name = "DB-vpc-b"
  }
}

# Create & Attach Internet Gateway to the vpc1:# VPC-A

resource "aws_internet_gateway" "gw1" {
  vpc_id = aws_vpc.a.id
  tags = {
    Name = "IGW_vpc_a"
  }
  depends_on = [aws_internet_gateway.gw1]
}

# Create & Attach Internet Gateway to the vpc2:# VPC-B

resource "aws_internet_gateway" "gw2" {
  vpc_id = aws_vpc.b.id
  tags = {
    Name = "IGW_vpc_b"
  }
  depends_on = [aws_internet_gateway.gw2]
}

# Create & Attach NAT Gateway to the VPC

resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.web1.id
  tags = {
    "Name" = "NatGateway"
  }
}

# Create Route Tables & Attach to Corresponding Subnets for vpc1: VPC-A

resource "aws_route_table" "r1" {
  vpc_id = aws_vpc.a.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw1.id
  }

  tags = {
    Name = "Public Route Table"
  }
  depends_on = [aws_internet_gateway.gw1]
}

resource "aws_route_table" "r2" {
  vpc_id = aws_vpc.a.id
  route {
    cidr_block = "11.20.4.0/24"
    gateway_id = aws_vpc_peering_connection.Prod-Dev.id
  }
  tags = {
    Name = "Private Route Table"
  }
  depends_on = [aws_vpc_peering_connection.Prod-Dev]
}

resource "aws_route_table" "r3" {
  vpc_id = aws_vpc.a.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat_gateway.id
  }

  tags = {
    Name = "Private Route Table with Internet Requests"
  }
  depends_on = [aws_internet_gateway.gw1]
}

# Create Route Tables & Attach to Corresponding Subnets for vpc2: VPC-B

resource "aws_route_table" "r4" {
  vpc_id = aws_vpc.b.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw2.id
  }

  tags = {
    Name = "Public Route Table vpc-b"
  }
  depends_on = [aws_internet_gateway.gw2]
}

resource "aws_route_table" "r5" {
  vpc_id = aws_vpc.b.id
  route {
    cidr_block = "10.20.4.0/24"
    gateway_id = aws_vpc_peering_connection.Prod-Dev.id
  }
  tags = {
    Name = "Private Route Table vpc-b"
  }
  depends_on = [aws_vpc_peering_connection.Prod-Dev]
}

# Attach subnet to Route Table

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.web1.id
  route_table_id = aws_route_table.r1.id
}
resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.app2.id
  route_table_id = aws_route_table.r2.id
}
resource "aws_route_table_association" "c" {
  subnet_id      = aws_subnet.DB1.id
  route_table_id = aws_route_table.r2.id
}
resource "aws_route_table_association" "e" {
  subnet_id      = aws_subnet.app1.id
  route_table_id = aws_route_table.r3.id
}
resource "aws_route_table_association" "f" {
  subnet_id      = aws_subnet.DBCache.id
  route_table_id = aws_route_table.r3.id
}
resource "aws_route_table_association" "g" {
  subnet_id      = aws_subnet.web2.id
  route_table_id = aws_route_table.r4.id
}
resource "aws_route_table_association" "h" {
  subnet_id      = aws_subnet.DB2.id
  route_table_id = aws_route_table.r5.id
}

resource "aws_security_group" "all_traffic1" {
  name        = "SG_VPC"
  description = "Allow inbound traffic"
  vpc_id      = aws_vpc.a.id

  ingress {
    description = "TLS from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.a.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  depends_on = [aws_vpc.a]

  tags = {
    Name = "allow_ssh"
  }
}

resource "aws_security_group_rule" "ssh_inbound_access1" {
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.all_traffic1.id
  to_port           = 22
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group" "all_traffic2" {
  name        = "SG_VPC"
  description = "Allow inbound traffic"
  vpc_id      = aws_vpc.b.id

  ingress {
    description = "TLS from VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.b.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  depends_on = [aws_vpc.b]

  tags = {
    Name = "allow_ssh"
  }
}

resource "aws_security_group_rule" "ssh_inbound_access2" {
  from_port         = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.all_traffic2.id
  to_port           = 22
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
}

# VPC Peering Connection

resource "aws_vpc_peering_connection" "Prod-Dev" {
  peer_vpc_id = aws_vpc.a.id
  vpc_id      = aws_vpc.b.id
  auto_accept = true
}

# Create EC2 instances in their respective VPCs

resource "aws_instance" "web1" {
  ami                         = "ami-0885b1f6bd170450c"
  instance_type               = "t2.micro"
  key_name                    = "vpc_prod"
  vpc_security_group_ids      = ["${aws_security_group.all_traffic1.id}"]
  associate_public_ip_address = true

  tags = {
    Name = "web-prod"
  }
  subnet_id = aws_subnet.web1.id

}

resource "aws_instance" "web2" {
  ami             = "ami-0885b1f6bd170450c"
  instance_type   = "t2.micro"
  key_name        = "vpc_prod"
  vpc_security_group_ids = ["${aws_security_group.all_traffic2.id}"]

  tags = {
    Name = "web-development"
  }
  subnet_id     = aws_subnet.web2.id
}