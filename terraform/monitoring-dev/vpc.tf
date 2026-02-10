# -----------------------------------------------------
# Monitoring Subnet (in Dev VPC)
# -----------------------------------------------------

resource "aws_subnet" "monitoring" {
  vpc_id                  = data.aws_vpc.dev.id
  cidr_block              = var.monitoring_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-subnet"
  }
}

# -----------------------------------------------------
# Route Table for Monitoring Subnet
# -----------------------------------------------------

resource "aws_route_table" "monitoring" {
  vpc_id = data.aws_vpc.dev.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.aws_internet_gateway.dev.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rt"
  }
}

resource "aws_route_table_association" "monitoring" {
  subnet_id      = aws_subnet.monitoring.id
  route_table_id = aws_route_table.monitoring.id
}
