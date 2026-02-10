# -----------------------------------------------------
# VPC (refit-prod-v2-vpc, 10.2.0.0/16)
# -----------------------------------------------------

resource "aws_vpc" "prod_v2" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

# -----------------------------------------------------
# Internet Gateway
# -----------------------------------------------------

resource "aws_internet_gateway" "prod_v2" {
  vpc_id = aws_vpc.prod_v2.id

  tags = {
    Name = "${local.name}-igw"
  }
}

# -----------------------------------------------------
# Public Subnets (ALB, NAT)
# -----------------------------------------------------

resource "aws_subnet" "prod_v2_public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.prod_v2.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-${var.availability_zones[count.index] == "ap-northeast-2a" ? "2a" : "2c"}"
    Type = "public"
  }
}

# -----------------------------------------------------
# Private Subnets - Backend (ASG)
# -----------------------------------------------------

resource "aws_subnet" "prod_v2_private_backend" {
  count = length(var.private_backend_subnet_cidrs)

  vpc_id            = aws_vpc.prod_v2.id
  cidr_block        = var.private_backend_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${local.name}-private-backend-${var.availability_zones[count.index] == "ap-northeast-2a" ? "2a" : "2c"}"
    Type = "private"
  }
}

# -----------------------------------------------------
# Private Subnets - Data (RDS, ElastiCache)
# -----------------------------------------------------

resource "aws_subnet" "prod_v2_private_data" {
  count = length(var.private_data_subnet_cidrs)

  vpc_id            = aws_vpc.prod_v2.id
  cidr_block        = var.private_data_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${local.name}-private-data-${var.availability_zones[count.index] == "ap-northeast-2a" ? "2a" : "2c"}"
    Type = "private"
  }
}

# -----------------------------------------------------
# NAT Gateway (single for cost; in first public subnet)
# -----------------------------------------------------

resource "aws_eip" "prod_v2_nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.prod_v2]
}

resource "aws_nat_gateway" "prod_v2" {
  allocation_id = aws_eip.prod_v2_nat.id
  subnet_id     = aws_subnet.prod_v2_public[0].id

  tags = {
    Name = "${local.name}-nat"
  }

  depends_on = [aws_internet_gateway.prod_v2]
}

# -----------------------------------------------------
# Route Tables - Public
# -----------------------------------------------------

resource "aws_route_table" "prod_v2_public" {
  vpc_id = aws_vpc.prod_v2.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.prod_v2.id
  }

  tags = {
    Name = "${local.name}-public-rt"
  }
}

resource "aws_route_table_association" "prod_v2_public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.prod_v2_public[count.index].id
  route_table_id = aws_route_table.prod_v2_public.id
}

# -----------------------------------------------------
# Route Tables - Private Backend
# -----------------------------------------------------

resource "aws_route_table" "prod_v2_private_backend" {
  vpc_id = aws_vpc.prod_v2.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.prod_v2.id
  }

  tags = {
    Name = "${local.name}-private-backend-rt"
  }
}

resource "aws_route_table_association" "prod_v2_private_backend" {
  count = length(var.private_backend_subnet_cidrs)

  subnet_id      = aws_subnet.prod_v2_private_backend[count.index].id
  route_table_id = aws_route_table.prod_v2_private_backend.id
}

# -----------------------------------------------------
# Route Tables - Private Data
# -----------------------------------------------------

resource "aws_route_table" "prod_v2_private_data" {
  vpc_id = aws_vpc.prod_v2.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.prod_v2.id
  }

  tags = {
    Name = "${local.name}-private-data-rt"
  }
}

resource "aws_route_table_association" "prod_v2_private_data" {
  count = length(var.private_data_subnet_cidrs)

  subnet_id      = aws_subnet.prod_v2_private_data[count.index].id
  route_table_id = aws_route_table.prod_v2_private_data.id
}

# -----------------------------------------------------
# VPC Gateway Endpoint (S3 - no NAT cost)
# -----------------------------------------------------

resource "aws_vpc_endpoint" "prod_v2_s3" {
  vpc_id            = aws_vpc.prod_v2.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.prod_v2_private_backend.id,
    aws_route_table.prod_v2_private_data.id
  ]

  tags = {
    Name = "${local.name}-s3-endpoint"
  }
}
