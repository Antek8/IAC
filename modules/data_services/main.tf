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
data "aws_caller_identity" "current" {}

data "aws_ssm_parameter" "ecs_ami_arm64" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id"
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
resource "aws_iam_role_policy" "qdrant_cloudwatch_policy" {
  name = "${var.name}-qdrant-cloudwatch-policy"
  role = aws_iam_role.qdrant_ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "CloudWatchLogs",
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:${var.name}-qdrant-ec2-logs:*"      }
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

resource "aws_launch_template" "qdrant" {
  name_prefix   = "${var.name}-qdrant-lt-"
  image_id      = data.aws_ssm_parameter.ecs_ami_arm64.value
  instance_type = var.qdrant_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.qdrant_ec2_profile.name
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  network_interfaces {
    device_index    = 0
    security_groups = [aws_security_group.data_services_sg.id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
      encrypted   = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/qdrant_user_data.sh.tpl", {
    efs_id = var.qdrant_efs_id
    region = var.region
    name   = var.name
  }))
}
resource "aws_iam_role_policy" "qdrant_s3_policy" {
  name = "${var.name}-qdrant-s3-policy"
  role = aws_iam_role.qdrant_ec2_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowS3Access",
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::*",
          "arn:aws:s3:::*/*"
        ]
      }
    ]
  })
}
resource "aws_autoscaling_group" "qdrant" {
  name                = "${var.name}-qdrant-asg"
  vpc_zone_identifier = var.private_subnet_ids
  min_size            = var.qdrant_min_size
  max_size            = var.qdrant_max_size
  desired_capacity    = var.qdrant_desired_capacity

  launch_template {
    id      = aws_launch_template.qdrant.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-qdrant"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "qdrant_scale_up" {
  name                   = "${var.name}-qdrant-scale-up"
  autoscaling_group_name = aws_autoscaling_group.qdrant.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "qdrant_cpu_high" {
  alarm_name          = "${var.name}-qdrant-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "70"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.qdrant.name
  }
  alarm_actions = [aws_autoscaling_policy.qdrant_scale_up.arn]
}

resource "aws_autoscaling_policy" "qdrant_scale_down" {
  name                   = "${var.name}-qdrant-scale-down"
  autoscaling_group_name = aws_autoscaling_group.qdrant.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 600
}

resource "aws_cloudwatch_metric_alarm" "qdrant_cpu_low" {
  alarm_name          = "${var.name}-qdrant-cpu-low"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "600"
  statistic           = "Average"
  threshold           = "30"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.qdrant.name
  }
  alarm_actions = [aws_autoscaling_policy.qdrant_scale_down.arn]
}


###############################################################################
# 2 Secrets Manager
###############################################################################
resource "aws_secretsmanager_secret" "this" {
  for_each                = var.secrets
  name                    = "/magi/${var.tenant_id}/${each.key}"
  description             = "Auto-generated secret for ${each.key}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "this" {
  for_each      = var.secrets
  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = each.value
}

