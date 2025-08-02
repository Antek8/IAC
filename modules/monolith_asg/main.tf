# modules/monolith_asg/main.tf

###############################################################################
# 1 Monolith EC2 Security Group
###############################################################################
resource "aws_security_group" "monolith" {
  name        = "${var.name}-sg"
  description = "Allow HTTP inbound to Monolith (React + Supertokens)"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id] # Changed from cidr_blocks
    description     = "Allow traffic from ALB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group_rule" "allow_ssh_from_jump_host" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = var.jump_host_security_group_id
  security_group_id        = aws_security_group.monolith.id
  description              = "Allow SSH from jump host"
}
###############################################################################
# 2 Launch Template
###############################################################################
data "aws_ami" "linux_arm" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-arm64-gp2"]
  }
}

resource "aws_launch_template" "monolith" {
  name_prefix   = "${var.name}-lt-"
  image_id      = data.aws_ami.linux_arm.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.monolith_profile.name
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  network_interfaces {
    subnet_id                   = element(var.private_subnet_ids, 0)
    security_groups             = [aws_security_group.monolith.id]
    associate_public_ip_address = false
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    region             = var.region
    monolith_image_uri = var.monolith_image_uri
  }))
}

###############################################################################
# 3 ASG
###############################################################################
resource "aws_autoscaling_group" "monolith_asg" {
  name = "${var.name}-asg"
  launch_template {
    id      = aws_launch_template.monolith.id
    version = "$Latest"
  }
  min_size            = var.min_size
  max_size            = 4
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.private_subnet_ids
  target_group_arns = [var.target_group_arn]

  health_check_type = "EC2"

  tag {
    key                 = "Name"
    value               = "${var.name}-monolith"
    propagate_at_launch = true
  }
}


##################################################################
### IAM Role for Monolith EC2 ###
##################################################################
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "monolith_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monolith_role" {
  name               = "${var.name}-monolith-role"
  assume_role_policy = data.aws_iam_policy_document.monolith_assume.json
}

# ADDED: Attaching the specified managed policies directly to the role.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.monolith_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecs_for_ec2" {
  role       = aws_iam_role.monolith_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.monolith_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


# UPDATED: Replaced the previous broad policy with the new least-privilege inline policy.
data "aws_iam_policy_document" "monolith_policy" {
  # This policy grants the Monolith (UI) ASG the permissions it needs to
  # serve the frontend, interact with the backend, and manage assets.

  statement {
    sid    = "APIGatewayInvoke"
    effect = "Allow"
    actions = [
      "execute-api:Invoke"
    ]
    # Allows the monolith's backend to call the API Gateway endpoint
    # to initiate the secure file upload process.
    resources = ["arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:*/*"]
  }

  statement {
    sid    = "AppS3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    # Allows the application to read and write its own static assets,
    # such as images, CSS, or user-generated content for the UI.
    resources = [
      "arn:aws:s3:::${var.assets_bucket}",
      "arn:aws:s3:::${var.assets_bucket}/*"
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
    # Allows the EC2 instances to write application and system logs.
    resources = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ec2/${var.name}-*"]
  }
}

resource "aws_iam_role_policy" "monolith_policy" {
  name   = "${var.name}-monolith-inline-policy"
  role   = aws_iam_role.monolith_role.id
  policy = data.aws_iam_policy_document.monolith_policy.json
}

resource "aws_iam_instance_profile" "monolith_profile" {
  name = "${var.name}-monolith-profile"
  role = aws_iam_role.monolith_role.name
}

###############################################################################
# 5 ECR Repository
###############################################################################
resource "aws_ecr_repository" "monolith" {
  name = lower("${var.name}-monolith")
}

###############################################################################
# 6 Auto Scaling Policies
###############################################################################

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.name}-scale-up"
  autoscaling_group_name = aws_autoscaling_group.monolith_asg.name
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
    AutoScalingGroupName = aws_autoscaling_group.monolith_asg.name
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.scale_up.arn]
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.name}-scale-down"
  autoscaling_group_name = aws_autoscaling_group.monolith_asg.name
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
    AutoScalingGroupName = aws_autoscaling_group.monolith_asg.name
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.scale_down.arn]
}
