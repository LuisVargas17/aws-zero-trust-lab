resource "aws_vpc" "frontend" {
  cidr_block           = var.frontend_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${var.project_name}-frontend-vpc" }
}

resource "aws_internet_gateway" "frontend" {
  vpc_id = aws_vpc.frontend.id
  tags   = { Name = "${var.project_name}-frontend-igw" }
}

resource "aws_subnet" "frontend_public" {
  vpc_id                  = aws_vpc.frontend.id
  cidr_block              = var.frontend_public_subnet_cidr
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-frontend-public-subnet" }
}

resource "aws_route_table" "frontend_public" {
  vpc_id = aws_vpc.frontend.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.frontend.id
  }
  tags = { Name = "${var.project_name}-frontend-public-rt" }
}

resource "aws_route_table_association" "frontend_public" {
  subnet_id      = aws_subnet.frontend_public.id
  route_table_id = aws_route_table.frontend_public.id
}

resource "aws_vpc" "backend" {
  cidr_block           = var.backend_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${var.project_name}-backend-vpc" }
}

resource "aws_internet_gateway" "backend" {
  vpc_id = aws_vpc.backend.id
  tags   = { Name = "${var.project_name}-backend-egress-igw" }
}

resource "aws_subnet" "backend_nat_public" {
  vpc_id                  = aws_vpc.backend.id
  cidr_block              = var.backend_nat_public_subnet_cidr
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.project_name}-backend-nat-public-subnet" }
}

resource "aws_route_table" "backend_nat_public" {
  vpc_id = aws_vpc.backend.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.backend.id
  }
  tags = { Name = "${var.project_name}-backend-nat-public-rt" }
}

resource "aws_route_table_association" "backend_nat_public" {
  subnet_id      = aws_subnet.backend_nat_public.id
  route_table_id = aws_route_table.backend_nat_public.id
}

resource "aws_eip" "backend_nat" {
  domain = "vpc"
  tags   = { Name = "${var.project_name}-backend-nat-eip" }
}

resource "aws_nat_gateway" "backend" {
  allocation_id = aws_eip.backend_nat.id
  subnet_id     = aws_subnet.backend_nat_public.id
  depends_on    = [aws_internet_gateway.backend]
  tags          = { Name = "${var.project_name}-backend-nat" }
}

resource "aws_subnet" "backend_private" {
  vpc_id                  = aws_vpc.backend.id
  cidr_block              = var.backend_private_subnet_cidr
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.project_name}-backend-private-subnet" }
}

resource "aws_route_table" "backend_private" {
  vpc_id = aws_vpc.backend.id
  route {
    cidr_block                = "0.0.0.0/0"
    nat_gateway_id            = aws_nat_gateway.backend.id
  }
  tags = { Name = "${var.project_name}-backend-private-rt" }
}

resource "aws_route_table_association" "backend_private" {
  subnet_id      = aws_subnet.backend_private.id
  route_table_id = aws_route_table.backend_private.id
}

resource "aws_vpc_peering_connection" "frontend_backend" {
  vpc_id      = aws_vpc.frontend.id
  peer_vpc_id = aws_vpc.backend.id
  auto_accept = true
  tags        = { Name = "${var.project_name}-frontend-backend-peering" }
}

resource "aws_route" "frontend_to_backend" {
  route_table_id            = aws_route_table.frontend_public.id
  destination_cidr_block    = var.backend_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.frontend_backend.id
}

resource "aws_route" "backend_to_frontend" {
  route_table_id            = aws_route_table.backend_private.id
  destination_cidr_block    = var.frontend_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.frontend_backend.id
}
