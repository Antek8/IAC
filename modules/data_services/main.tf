# modules/data_services/main.tf

###############################################################################
# 0 Security Group for Data Services (Redis & Qdrant)
###############################################################################
resource "aws_security_group" "data_services_sg" {
  name        = "${var.name}-data-sg"
  description = "Allow Agentic ASG to access Redis(6379) & Qdrant(6333)"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 1 Redis Subnet Group & Replication Group
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.name}-redis-subnet-group"
  subnet_ids = var.private_subnet_ids
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.name}-redis"
  description          = "Redis for ${var.name}"
  node_type            = var.redis_node_type
  num_cache_clusters   = var.redis_num_clusters
  # FIXED: Set automatic failover dynamically based on the number of clusters.
  # This requires at least 2 clusters.
  automatic_failover_enabled = var.redis_num_clusters > 1
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = [aws_security_group.data_services_sg.id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
}

# 2 ECS cluster (for Qdrant)
resource "aws_ecs_cluster" "qdrant" {
  name = "${var.name}-qdrant-cluster"
}

# 3 ECR repo (optional) & ECS task/service
resource "aws_ecr_repository" "qdrant" {
  name                 = "${var.name}-qdrant-repo"
  image_tag_mutability = "MUTABLE"
}

data "aws_iam_policy_document" "ecs_exec_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_exec_role" {
  name               = "${var.name}-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_exec_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_exec_policy" {
  role       = aws_iam_role.ecs_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_cloudwatch_log_group" "qdrant" {
  name = "/ecs/${var.name}-qdrant"
}


resource "aws_ecs_task_definition" "qdrant" {
  family                   = "${var.name}-qdrant"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_exec_role.arn

  container_definitions = jsonencode([{
    name      = "qdrant"
    image     = var.qdrant_container_image
    essential = true
    portMappings = [{
      containerPort = 6333
      hostPort      = 6333
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.qdrant.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "qdrant" {
  name            = "${var.name}-qdrant-svc"
  cluster         = aws_ecs_cluster.qdrant.id
  task_definition = aws_ecs_task_definition.qdrant.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [aws_security_group.data_services_sg.id]
  }
}

# 4 Secrets Manager (optional keys)
resource "aws_secretsmanager_secret" "this" {
  for_each    = var.secrets
  name        = "/myapp/${var.tenant_id}/${each.key}"
  description = "Auto-generated secret for ${each.key}"
}

resource "aws_secretsmanager_secret_version" "this" {
  for_each      = var.secrets
  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = each.value
}
