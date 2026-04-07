# -----------------------------------------------------
# VPC & Networking (refit prod v3 - self-managed K8s)
# -----------------------------------------------------

# ------- VPC -------
resource "aws_vpc" "k8s" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.prefix}-vpc" }
}

# ------- Internet Gateway -------
resource "aws_internet_gateway" "k8s" {
  vpc_id = aws_vpc.k8s.id

  tags = { Name = "${local.prefix}-igw" }
}

# ------- Public Subnets (3 AZs) -------
resource "aws_subnet" "pub_a" {
  vpc_id                  = aws_vpc.k8s.id
  cidr_block              = var.subnet_pub_a_cidr
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true

  tags = { Name = "${local.prefix}-pub-a" }
}

resource "aws_subnet" "pub_b" {
  vpc_id                  = aws_vpc.k8s.id
  cidr_block              = var.subnet_pub_b_cidr
  availability_zone       = "ap-northeast-2b"
  map_public_ip_on_launch = true

  tags = { Name = "${local.prefix}-pub-b" }
}

resource "aws_subnet" "pub_c" {
  vpc_id                  = aws_vpc.k8s.id
  cidr_block              = var.subnet_pub_c_cidr
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = true

  tags = { Name = "${local.prefix}-pub-c" }
}

# ------- Route Table -------
resource "aws_route_table" "pub" {
  vpc_id = aws_vpc.k8s.id

  # Default route to IGW
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s.id
  }

  # Route to prod-v2 VPC via peering (RDS, ElastiCache 접근)
  route {
    cidr_block                = var.prod_v2_vpc_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.k8s_to_prod_v2.id
  }

  tags = { Name = "${local.prefix}-pub-rt" }
}

resource "aws_route_table_association" "pub_a" {
  subnet_id      = aws_subnet.pub_a.id
  route_table_id = aws_route_table.pub.id
}

resource "aws_route_table_association" "pub_b" {
  subnet_id      = aws_subnet.pub_b.id
  route_table_id = aws_route_table.pub.id
}

resource "aws_route_table_association" "pub_c" {
  subnet_id      = aws_subnet.pub_c.id
  route_table_id = aws_route_table.pub.id
}

# ------- VPC Peering (k8s VPC → prod-v2 VPC) -------
# prod-v2 VPC의 RDS/ElastiCache/MSK 등에 접근하기 위한 피어링
resource "aws_vpc_peering_connection" "k8s_to_prod_v2" {
  vpc_id      = aws_vpc.k8s.id
  peer_vpc_id = var.prod_v2_vpc_id
  auto_accept = true # 동일 계정이므로 자동 수락

  tags = { Name = "k8s-to-rds-peering" }
}

# ------- Subnet map (for ec2 lookups) -------
locals {
  subnet_ids = {
    pub_a = aws_subnet.pub_a.id
    pub_b = aws_subnet.pub_b.id
    pub_c = aws_subnet.pub_c.id
  }
}
