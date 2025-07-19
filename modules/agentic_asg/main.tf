# modules/agentic_asg/main.tf

###############################################################################
# 1 Security Group
###############################################################################
resource "aws_security_group" "agentic_sg" {
  name        = "${var.name}-agentic-sg"
  description = "Allow web ASG to talk to Agentic logic"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allowed_source_security_group_ids
    content {
      from_port       = 80
      to_port         = 80
      protocol        = "tcp"
      security_groups = [ingress.value]
      description     = "Allow web ASG"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

###############################################################################
# 2 IAM Role & Instance Profile
###############################################################################
# ADDED: Data source to get the current AWS account ID for IAM policy construction.
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "agentic_role" {
  name               = "${var.name}-agentic-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role_policy_attachment" "agentic_ssm_policy" {
  role       = aws_iam_role.agentic_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attaching the read-only ECR policy is the best practice for this.
resource "aws_iam_role_policy_attachment" "agentic_ecr_policy" {
  role       = aws_iam_role.agentic_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# UPDATED: This policy now reflects the least-privilege permissions required.
data "aws_iam_policy_document" "agentic_policy" {
  # This policy grants the Agentic ASG the core permissions it needs to
  # process prompts and generate AI responses.

  statement {
    sid       = "BedrockInvoke"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    # Scoped to all models for simplicity, but can be restricted to specific model ARNs.
    resources = ["*"]
  }

  statement {
    sid       = "SecretsManagerRead"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    # Allows reading any secret under the application's path.
    # This is necessary to fetch the Qdrant API key and other credentials.
    resources = ["arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:/myapp/${var.tenant_id}/*"]
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    # Allows the EC2 instances to write logs for monitoring and debugging.
    resources = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ec2/${var.name}-*"]
  }
}

resource "aws_iam_role_policy" "agentic_policy" {
  name   = "${var.name}-agentic-inline-policy"
  role   = aws_iam_role.agentic_role.id
  policy = data.aws_iam_policy_document.agentic_policy.json
}
resource "aws_iam_instance_profile" "agentic_profile" {
  name = "${var.name}-agentic-profile"
  role = aws_iam_role.agentic_role.name
}

###############################################################################
# 3 Launch Template
###############################################################################
data "aws_ami" "linux_arm" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-arm64-gp2"]
  }
}

resource "aws_launch_template" "agentic_lt" {
  name_prefix   = "${var.name}-agentic-lt-"
  image_id      = data.aws_ami.linux_arm.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.agentic_profile.name
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  network_interfaces {
    device_index                = 0
    subnet_id                   = element(var.private_subnet_ids, 0)
    security_groups             = [aws_security_group.agentic_sg.id]
    associate_public_ip_address = false
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    region            = var.region
    agentic_image_uri = var.agentic_image_uri
  }))
}

###############################################################################
# 4 Auto Scaling Group
###############################################################################
resource "aws_autoscaling_group" "agentic_asg" {
  name                = "${var.name}-agentic-asg"
  min_size            = var.min_size
  max_size            = 4
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.private_subnet_ids

  launch_template {
    id      = aws_launch_template.agentic_lt.id
    version = "$Latest"
  }

  health_check_type = "EC2"

  tag {
    key                 = "Name"
    value               = "${var.name}-agentic"
    propagate_at_launch = true
  }
}

###############################################################################
# 5 ECR Repository & CloudWatch Logs
###############################################################################
resource "aws_ecr_repository" "agentic" {
  name = lower("${var.name}-agentic")
}

resource "aws_cloudwatch_log_group" "agentic_asg_logs" {
  name              = "/aws/ec2/${var.name}-agentic"
  retention_in_days = 7
}

###############################################################################
# 6 Auto Scaling Policies
###############################################################################

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.name}-scale-up"
  autoscaling_group_name = aws_autoscaling_group.agentic_asg.name
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
    AutoScalingGroupName = aws_autoscaling_group.agentic_asg.name
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.scale_up.arn]
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.name}-scale-down"
  autoscaling_group_name = aws_autoscaling_group.agentic_asg.name
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
    AutoScalingGroupName = aws_autoscaling_group.agentic_asg.name
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.scale_down.arn]
}
