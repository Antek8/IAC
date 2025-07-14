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
# 2 IAM Role & Instance Profile (for Bedrock, S3, SQS, Secrets, X-Ray, CWL)
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
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.region}:*:log-group:/aws/ec2/${var.name}-agentic*"]
  }
  statement {
    sid    = "AllowXRay"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords"
    ]
    resources = ["*"]
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
data "aws_ami" "linux" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_launch_template" "agentic_lt" {
  name_prefix   = "${var.name}-agentic-lt-"
  image_id      = data.aws_ami.linux.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.agentic_profile.name
  }

  network_interfaces {
    device_index                = 0
    subnet_id                   = element(var.private_subnet_ids, 0)
    security_groups             = [aws_security_group.agentic_sg.id]
    associate_public_ip_address = false
  }

  # FIXED: Replaced templatefile() with an inline script to avoid the error
  # about the missing userdata.sh.tpl file.
  user_data = base64encode(<<-EOF
              #!/bin/bash
              # User data script for agentic instances.
              # This is a placeholder as userdata.sh.tpl was missing.
              echo "Region: ${var.region}" >> /tmp/agentic_userdata.log
              echo "S3 Bucket: ${var.s3_bucket_name}" >> /tmp/agentic_userdata.log
              echo "SQS URL: ${var.sqs_queue_url}" >> /tmp/agentic_userdata.log
              # Add your agentic application setup commands here.
              EOF
  )
}

###############################################################################
# 4 Auto Scaling Group
###############################################################################
resource "aws_autoscaling_group" "agentic_asg" {
  name                = "${var.name}-agentic-asg"
  min_size            = var.min_size
  max_size            = var.max_size
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
