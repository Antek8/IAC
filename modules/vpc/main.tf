# modules/vpc/main.tf

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name}-vpc" }
}

data "aws_availability_zones" "azs" {}

# FIXED: Changed for_each to count to use a numeric index for availability_zone
resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  availability_zone = data.aws_availability_zones.azs.names[count.index]
  cidr_block        = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  tags              = { Name = "${var.name}-public-${count.index}" }
}

# FIXED: Changed for_each to count to use a numeric index for availability_zone
resource "aws_subnet" "private_app" {
  count             = length(var.private_app_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  availability_zone = data.aws_availability_zones.azs.names[count.index]
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  tags              = { Name = "${var.name}-priv-app-${count.index}" }
}

# FIXED: Changed for_each to count to use a numeric index for availability_zone
resource "aws_subnet" "private_rag" {
  count             = length(var.private_rag_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  availability_zone = data.aws_availability_zones.azs.names[count.index]
  cidr_block        = var.private_rag_subnet_cidrs[count.index]
  tags              = { Name = "${var.name}-priv-rag-${count.index}" }
}

# 2 Internet Gateway & Route Table
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.name}-public-rt" }
}

# FIXED: Changed for_each to count to associate with the correct subnets
resource "aws_route_table_association" "public_assoc" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# 3 Elastic IP and NAT Gateway for outbound internet
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id # Place NAT in the first public subnet
  tags          = { Name = "${var.name}-nat-gw" }
  depends_on    = [aws_internet_gateway.igw]
}

# Create a new route table for private subnets to use the NAT Gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = { Name = "${var.name}-private-rt" }
}

# FIXED: Changed for_each to count to associate with the correct subnets
resource "aws_route_table_association" "private_app_assoc" {
  count          = length(var.private_app_subnet_cidrs)
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private.id
}

# FIXED: Changed for_each to count to associate with the correct subnets
resource "aws_route_table_association" "private_rag_assoc" {
  count          = length(var.private_rag_subnet_cidrs)
  subnet_id      = aws_subnet.private_rag[count.index].id
  route_table_id = aws_route_table.private.id
}


# 4 VPC Endpoints (S3 & DynamoDB gateway; SecretsManager, SQS & Bedrock interface)

# A security group for all interface endpoints to allow HTTPS from within the VPC
resource "aws_security_group" "vpc_endpoint_sg" {
  name        = "${var.name}-vpc-endpoint-sg"
  description = "Allow HTTPS from within the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Allow HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block] # Restrict to traffic from within this VPC
  }
}

# S3 Gateway Endpoint (already in your code, ensure route_table_ids includes all tables)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  # Associate with public and the new private route table
  route_table_ids = [aws_route_table.public.id, aws_route_table.private.id]
}

# DynamoDB Gateway Endpoint (already in your code, ensure route_table_ids includes all tables)
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  # Associate with public and the new private route table
  route_table_ids = [aws_route_table.public.id, aws_route_table.private.id]
}

# Secrets Manager Interface Endpoint (updated to use the new SG)
resource "aws_vpc_endpoint" "secrets" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
}

# SQS Interface Endpoint (updated to use the new SG)
resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.sqs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_rag[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
}

# *** NEW *** Bedrock Interface Endpoint
resource "aws_vpc_endpoint" "bedrock_runtime" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  # Place in app subnets where the agentic ASG runs
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
}
