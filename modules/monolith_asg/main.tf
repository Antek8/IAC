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
    cidr_blocks = ["0.0.0.0/0"]      # for MVP: allow all HTTP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
###############################################################################
# 2 Launch Template (attach the new SG)
###############################################################################

data "aws_ami" "linux" {
  owners      = ["amazon"]
  most_recent = true
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_launch_template" "monolith" {
  name_prefix   = "${var.name}-lt-"
  image_id = data.aws_ami.linux.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.monolith_profile.name
  }
  network_interfaces {
    subnet_id                   = element(var.private_subnet_ids, 0)
    security_groups             = [aws_security_group.monolith.id]
    associate_public_ip_address = false
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              # bootstrap your React + Supertokens app here
              EOF
  )
}

###############################################################################
# 3 ASG 
###############################################################################
resource "aws_autoscaling_group" "monolith_asg" {
  name               = "${var.name}-asg"
  launch_template {
    id      = aws_launch_template.monolith.id
    version = "$Latest"
  }
  min_size            = var.min_size
  max_size            = var.max_size
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

### Inline policy: Bedrock, S3, SQS, Secrets, Logs, X-Ray ###
data "aws_iam_policy_document" "monolith_policy" {
  statement {
    sid      = "Bedrock"
    effect   = "Allow"
    actions  = ["bedrock:*"]
    resources = ["*"]
  }
  statement {
    sid      = "S3"
    effect   = "Allow"
    actions  = ["s3:GetObject","s3:ListBucket"]
    resources = [
      "arn:aws:s3:::${var.assets_bucket}",
      "arn:aws:s3:::${var.assets_bucket}/*"
    ]
  }
  statement {
    sid      = "SQS"
    effect   = "Allow"
    actions  = ["sqs:SendMessage"]
    resources = [ var.sqs_queue_arn ]
  }
  statement {
    sid      = "SecretsManager"
    effect   = "Allow"
    actions  = ["secretsmanager:GetSecretValue"]
    resources = [ var.secrets_manager_secret_arn ]
  }
  statement {
    sid      = "CloudWatchLogs"
    effect   = "Allow"
    actions  = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.region}:*:log-group:/aws/ec2/${var.name}-*"]
  }
  statement {
    sid      = "XRay"
    effect   = "Allow"
    actions  = ["xray:PutTraceSegments","xray:PutTelemetryRecords"]
    resources = ["*"]
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
