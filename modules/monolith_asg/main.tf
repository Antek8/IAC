# modules/monolith/main.tf

###############################################################################
# 1 frontend EC2 Security Group
###############################################################################
locals {
  ssh_ips   = ["79.208.187.246/32", "95.91.247.58/32"]
  http_ips  = ["79.208.187.246/32", "95.91.247.58/32"]
  app_ports = [3000]
}

resource "aws_security_group" "frontend" {
  name        = "${var.name}-sg"
  description = "Frontend SG (HTTP + SSH + app)"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = local.ssh_ips
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = local.http_ips
    content {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "Allow HTTP traffic from specific IPs"
    }
  }

  dynamic "ingress" {
    for_each = local.http_ips
    content {
      from_port   = 3000
      to_port     = 3000
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  ingress {
    from_port                = 22
    to_port                  = 22
    protocol                 = "tcp"
    security_groups          = [var.jump_host_security_group_id]    
    description              = "Allow SSH from jump host"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

###############################################################################
# 2 Launch Template
###############################################################################
data "aws_ssm_parameter" "ecs_ami_arm64" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id"
}
resource "aws_launch_template" "frontend" {
  name_prefix   = "${var.name}-lt-"
  image_id = data.aws_ssm_parameter.ecs_ami_arm64.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.frontend_profile.name
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  network_interfaces {
    subnet_id                   = element(var.public_subnet_ids, 0)
    security_groups             = [aws_security_group.frontend.id]
    associate_public_ip_address = true
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
      encrypted   = true
      delete_on_termination = true
    }
  }
  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    region             = var.region
    frontend_image_uri = var.frontend_image_uri
  }))
}

###############################################################################
# 3 ASG
###############################################################################
resource "aws_autoscaling_group" "frontend_asg" {
  name = "${var.name}-asg"
  launch_template {
    id      = aws_launch_template.frontend.id
    version = "$Latest"
  }
  min_size            = var.min_size
  max_size            = 4
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.public_subnet_ids
  target_group_arns = [var.target_group_arn]

  health_check_type = "EC2"

  tag {
    key                 = "Name"
    value               = var.name
    propagate_at_launch = true
  }
}


##################################################################
### IAM Role for frontend EC2 ###
##################################################################
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "frontend_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "frontend_role" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.frontend_assume.json
}

# ADDED: Attaching the specified managed policies directly to the role.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.frontend_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecs_for_ec2" {
  role       = aws_iam_role.frontend_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.frontend_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


# UPDATED: Replaced the previous broad policy with the new least-privilege inline policy.
data "aws_iam_policy_document" "frontend_policy" {
  # This policy grants the frontend (UI) ASG the permissions it needs to
  # serve the frontend, interact with the backend, and manage assets.

  statement {
    sid    = "APIGatewayInvoke"
    effect = "Allow"
    actions = [
      "execute-api:Invoke"
    ]
    # Allows the frontend's backend to call the API Gateway endpoint
    # to initiate the secure file upload process.
    resources = ["arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:*/*"]
  }

  statement {
      sid    = "S3Access"
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ]
        resources = [
          "arn:aws:s3:::*",
          "arn:aws:s3:::*/*"
        ]
    }

  statement {
    sid    = "AppSecretsAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    # Allows the application to fetch its own necessary secrets,
    # like database passwords or third-party API keys.
    resources = ["arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:/${var.project}/${var.tenant_id}/*"]  
    }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    # Allows the EC2 instances to write application and system logs.
    resources = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ec2/${var.name}-*"]
  }
}

resource "aws_iam_role_policy" "frontend_policy" {
  name   = "${var.name}-inline-policy"
  role   = aws_iam_role.frontend_role.id
  policy = data.aws_iam_policy_document.frontend_policy.json
}

resource "aws_iam_instance_profile" "frontend_profile" {
  name = "${var.name}-profile"
  role = aws_iam_role.frontend_role.name
}

###############################################################################
# 5 ECR Repository
###############################################################################
resource "aws_ecr_repository" "frontend" {
  name = lower(var.name)
}

###############################################################################
# 6 Auto Scaling Policies
###############################################################################

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.name}-scale-up"
  autoscaling_group_name = aws_autoscaling_group.frontend_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300 # 5 minutes
}

resource "aws_cloudwatch_metric_alarm" "scale_up_alarm" {
  alarm_name          = "${var.name}-cpu-high-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300" # 5 minutes in seconds
  statistic           = "Average"
  threshold           = "70"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.frontend_asg.name
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.scale_up.arn]
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.name}-scale-down"
  autoscaling_group_name = aws_autoscaling_group.frontend_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 600 # 10 minutes
}

resource "aws_cloudwatch_metric_alarm" "scale_down_alarm" {
  alarm_name          = "${var.name}-cpu-low-alarm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "600" # 10 minutes in seconds
  statistic           = "Average"
  threshold           = "30"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.frontend_asg.name
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.scale_down.arn]
}
