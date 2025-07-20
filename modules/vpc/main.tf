# modules/vpc/main.tf

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name}-vpc" }
}

data "aws_availability_zones" "azs" {}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  availability_zone       = data.aws_availability_zones.azs.names[count.index]
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.name}-public-${count.index}" }
}

resource "aws_subnet" "private_app" {
  count             = length(var.private_app_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  availability_zone = data.aws_availability_zones.azs.names[count.index]
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  tags              = { Name = "${var.name}-priv-app-${count.index}" }
}

resource "aws_subnet" "private_rag" {
  count             = length(var.private_rag_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  availability_zone = data.aws_availability_zones.azs.names[count.index]
  cidr_block        = var.private_rag_subnet_cidrs[count.index]
  tags              = { Name = "${var.name}-priv-rag-${count.index}" }
}

# 2 Internet Gateway & Public Route Table
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

resource "aws_route_table_association" "public_assoc" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# 3. fck-nat Module for cost-effective NAT
module "fck_nat" {
  source = "github.com/RaJiska/terraform-aws-fck-nat"

  name      = "${var.name}-fck-nat"
  vpc_id    = aws_vpc.this.id
  subnet_id = aws_subnet.public[0].id
  ha_mode   = false

  update_route_tables = false
}

# 4. Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-private-rt" }
}

resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.fck_nat.eni_id
}

# Associate the private route table with the private subnets
resource "aws_route_table_association" "private_app_assoc" {
  count          = length(var.private_app_subnet_cidrs)
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_rag_assoc" {
  count          = length(var.private_rag_subnet_cidrs)
  subnet_id      = aws_subnet.private_rag[count.index].id
  route_table_id = aws_route_table.private.id
}


# 5. VPC Endpoints
resource "aws_security_group" "vpc_endpoint_sg" {
  name        = "${var.name}-vpc-endpoint-sg"
  description = "Allow HTTPS from within the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Allow HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }
}

# ADDED: A dedicated security group for the RAG Lambdas.
resource "aws_security_group" "rag_lambda_sg" {
  name        = "${var.name}-rag-lambda-sg"
  description = "Allow outbound traffic from RAG Lambdas"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-rag-lambda-sg"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id, aws_route_table.private.id]
}

resource "aws_vpc_endpoint" "secrets" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private_app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint_sg.id]
}

resource "aws_security_group" "alb_sg" {
  name        = "${var.name}-alb-sg"
  description = "Allow HTTPS inbound traffic to ALB"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Allow HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-alb-sg"
  }
}
