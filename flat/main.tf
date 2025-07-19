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

resource "aws_iam_role_policy_attachment" "agentic_ecr_policy" {
  role       = aws_iam_role.agentic_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

data "aws_iam_policy_document" "agentic_policy" {
  statement {
    sid       = "Bedrock"
    effect    = "Allow"
    actions   = ["bedrock:*"]
    resources = ["*"]
  }
  statement {
    sid    = "AllowS3"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::${var.s3_bucket_name}",
      "arn:aws:s3:::${var.s3_bucket_name}/*"
    ]
  }
  statement {
    sid    = "AllowSQS"
    effect = "Allow"
    actions = ["sqs:SendMessage"]
    resources = [var.sqs_queue_arn]
  }
  statement {
    sid    = "AllowSecrets"
    effect = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [var.secrets_manager_secret_arn]
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
  # UPDATED: max_size is now set to 4 as requested.
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

# ADDED: Policy to scale up the ASG by one instance.
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.name}-scale-up"
  autoscaling_group_name = aws_autoscaling_group.agentic_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300 # 5 minutes
}

# ADDED: CloudWatch alarm to trigger the scale-up policy when CPU is >= 70% for 5 minutes.
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

# ADDED: Policy to scale down the ASG by one instance.
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.name}-scale-down"
  autoscaling_group_name = aws_autoscaling_group.agentic_asg.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = -1
  cooldown               = 600 # 10 minutes
}

# ADDED: CloudWatch alarm to trigger the scale-down policy when CPU is <= 30% for 10 minutes.
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
