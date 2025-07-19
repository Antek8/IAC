# modules/data_services/main.tf

###############################################################################
# 0 Security Group for Data Services
###############################################################################
resource "aws_security_group" "data_services_sg" {
  name        = "${var.name}-data-sg"
  description = "Allow Agentic ASG to access Qdrant on port 6333"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

###############################################################################
# 1 Qdrant on EC2
###############################################################################

data "aws_ami" "ecs_optimized_arm" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-arm64-ebs"]
  }
}

resource "aws_iam_role" "qdrant_ec2_role" {
  name = "${var.name}-qdrant-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "qdrant_ssm_policy" {
  role       = aws_iam_role.qdrant_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "qdrant_ecr_pull_policy" {
  role       = aws_iam_role.qdrant_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "qdrant_ec2_profile" {
  name = "${var.name}-qdrant-ec2-profile"
  role = aws_iam_role.qdrant_ec2_role.name
}

resource "aws_instance" "qdrant" {
  ami                  = data.aws_ami.ecs_optimized_arm.id
  # FIXED: Use the new variable for the instance type.
  instance_type        = var.qdrant_instance_type
  subnet_id            = var.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.data_services_sg.id]
  iam_instance_profile = aws_iam_instance_profile.qdrant_ec2_profile.name

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = 30
  }

  user_data = <<-EOF
              #!/bin/bash
              # Create Docker daemon configuration file
              cat <<'EOT' > /etc/docker/daemon.json
              {
                "log-driver": "awslogs",
                "log-opts": {
                  "awslogs-group": "${var.name}-qdrant-ec2-logs",
                  "awslogs-region": "${var.region}",
                  "awslogs-create-group": "true"
                }
              }
              EOT

              # Restart Docker to apply the new configuration
              systemctl restart docker

              # Run Qdrant container, which will now log to CloudWatch automatically
              mkdir -p /opt/qdrant/storage
              docker run -d -p 6333:6333 -v /opt/qdrant/storage:/qdrant/storage qdrant/qdrant:latest
              EOF

  tags = {
    Name = "${var.name}-qdrant-ec2"
  }
}

###############################################################################
# 2 Secrets Manager
###############################################################################
resource "random_pet" "secret_suffix" {
  length = 2
}

resource "aws_secretsmanager_secret" "this" {
  for_each                = var.secrets
  name                    = "/myapp/${var.tenant_id}/${each.key}-${random_pet.secret_suffix.id}"
  description             = "Auto-generated secret for ${each.key}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "this" {
  for_each      = var.secrets
  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = each.value
}
