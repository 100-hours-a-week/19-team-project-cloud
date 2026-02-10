# -----------------------------------------------------
# 기존 VPC 조회 (use_existing_vpc=true일 때)
# -----------------------------------------------------

data "aws_vpc" "existing" {
  count = var.use_existing_vpc ? 1 : 0

  filter {
    name   = "tag:Name"
    values = [var.existing_vpc_name]
  }
}

# -----------------------------------------------------
# VPC·서브넷·NAT·라우트 (use_existing_vpc=false일 때만 생성)
# -----------------------------------------------------

resource "aws_vpc" "prod_v2" {
  count = var.use_existing_vpc ? 0 : 1

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

resource "aws_internet_gateway" "prod_v2" {
  count = var.use_existing_vpc ? 0 : 1

  vpc_id = aws_vpc.prod_v2[0].id

  tags = {
    Name = "${local.name}-igw"
  }
}

resource "aws_subnet" "prod_v2_public" {
  count = var.use_existing_vpc ? 0 : length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.prod_v2[0].id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-${var.availability_zones[count.index] == "ap-northeast-2a" ? "2a" : "2c"}"
    Type = "public"
  }
}

resource "aws_subnet" "prod_v2_private_backend" {
  count = var.use_existing_vpc ? 0 : length(var.private_backend_subnet_cidrs)

  vpc_id            = aws_vpc.prod_v2[0].id
  cidr_block        = var.private_backend_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${local.name}-private-backend-${var.availability_zones[count.index] == "ap-northeast-2a" ? "2a" : "2c"}"
    Type = "private"
  }
}

resource "aws_subnet" "prod_v2_private_data" {
  count = var.use_existing_vpc ? 0 : length(var.private_data_subnet_cidrs)

  vpc_id            = aws_vpc.prod_v2[0].id
  cidr_block        = var.private_data_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${local.name}-private-data-${var.availability_zones[count.index] == "ap-northeast-2a" ? "2a" : "2c"}"
    Type = "private"
  }
}

resource "aws_eip" "prod_v2_nat" {
  count = var.use_existing_vpc ? 0 : 1

  domain = "vpc"

  tags = {
    Name = "${local.name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.prod_v2]
}

resource "aws_nat_gateway" "prod_v2" {
  count = var.use_existing_vpc ? 0 : 1

  allocation_id = aws_eip.prod_v2_nat[0].id
  subnet_id     = aws_subnet.prod_v2_public[0].id

  tags = {
    Name = "${local.name}-nat"
  }

  depends_on = [aws_internet_gateway.prod_v2]
}

resource "aws_route_table" "prod_v2_public" {
  count = var.use_existing_vpc ? 0 : 1

  vpc_id = aws_vpc.prod_v2[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.prod_v2[0].id
  }

  tags = {
    Name = "${local.name}-public-rt"
  }
}

resource "aws_route_table_association" "prod_v2_public" {
  count = var.use_existing_vpc ? 0 : length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.prod_v2_public[count.index].id
  route_table_id = aws_route_table.prod_v2_public[0].id
}

resource "aws_route_table" "prod_v2_private_backend" {
  count = var.use_existing_vpc ? 0 : 1

  vpc_id = aws_vpc.prod_v2[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.prod_v2[0].id
  }

  tags = {
    Name = "${local.name}-private-backend-rt"
  }
}

resource "aws_route_table_association" "prod_v2_private_backend" {
  count = var.use_existing_vpc ? 0 : length(var.private_backend_subnet_cidrs)

  subnet_id      = aws_subnet.prod_v2_private_backend[count.index].id
  route_table_id = aws_route_table.prod_v2_private_backend[0].id
}

resource "aws_route_table" "prod_v2_private_data" {
  count = var.use_existing_vpc ? 0 : 1

  vpc_id = aws_vpc.prod_v2[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.prod_v2[0].id
  }

  tags = {
    Name = "${local.name}-private-data-rt"
  }
}

resource "aws_route_table_association" "prod_v2_private_data" {
  count = var.use_existing_vpc ? 0 : length(var.private_data_subnet_cidrs)

  subnet_id      = aws_subnet.prod_v2_private_data[count.index].id
  route_table_id = aws_route_table.prod_v2_private_data[0].id
}

resource "aws_vpc_endpoint" "prod_v2_s3" {
  count = var.use_existing_vpc ? 0 : 1

  vpc_id            = aws_vpc.prod_v2[0].id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.prod_v2_private_backend[0].id,
    aws_route_table.prod_v2_private_data[0].id
  ]

  tags = {
    Name = "${local.name}-s3-endpoint"
  }
}
