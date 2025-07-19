# modules/monolith_asg/main.tf

###############################################################################
# 1 Monolith EC2 Security Group
###############################################################################
resource "aws_security_group" "monolith" {
  name        = "${var.name}-sg"
  description = "Allow HTTP inbound to Monolith (React + Supertokens)"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
  # UPDATED: max_size is now set to 4 as requested.
  max_size            = 4
  desired_capacity    = var.desired_capacity
  vpc_zone_identifier = var.private_subnet_ids

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


# This is the correct least-privilege inline policy.
data "aws_iam_policy_document" "monolith_policy" {
  statement {
    sid    = "InvokeBedrock"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel"
    ]
    resources = [
      "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:inference-profile/eu.meta.llama3-2-3b-instruct-v1:0",
      "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/meta.llama3-2-3b-instruct-v1:0"
    ]
  }
  statement {
    sid    = "AppS3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    # FIXED: The resource strings now correctly construct the S3 bucket ARN.
    resources = [
      "arn:aws:s3:::${var.assets_bucket}",
      "arn:aws:s3:::${var.assets_bucket}/*"
    ]
  }
  statement {
    sid    = "AppSQSAccess"
    effect = "Allow"
    actions = [
      "sqs:*"
    ]
    resources = [var.sqs_queue_arn]
  }
  statement {
    sid    = "AppSecretsAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = ["arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:/myapp/*"]
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

# ADDED: Policy to scale up the ASG by one instance.
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.name}-scale-up"
  autoscaling_group_name = aws_autoscaling_group.monolith_asg.name
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
    AutoScalingGroupName = aws_autoscaling_group.monolith_asg.name
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.scale_up.arn]
}

# ADDED: Policy to scale down the ASG by one instance.
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.name}-scale-down"
  autoscaling_group_name = aws_autoscaling_group.monolith_asg.name
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
    AutoScalingGroupName = aws_autoscaling_group.monolith_asg.name
  }

  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions     = [aws_autoscaling_policy.scale_down.arn]
}
