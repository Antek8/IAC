data "aws_iam_policy_document" "assume_ec2" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "agentic_role" {
  name               = "${var.name}-agentic-role"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

data "aws_iam_policy_document" "agentic_policy" {
  statement {
    sid      = "AllowBedrock"
    effect   = "Allow"
    actions  = ["bedrock:*"]
    resources = ["*"]
  }
  statement {
    sid      = "AllowS3"
    effect   = "Allow"
    actions  = [
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
    sid      = "AllowSQS"
    effect   = "Allow"
    actions  = ["sqs:SendMessage"]
    resources = [var.sqs_queue_arn]
  }
  statement {
    sid      = "AllowSecrets"
    effect   = "Allow"
    actions  = ["secretsmanager:GetSecretValue"]
    resources = [var.secrets_manager_secret_arn]
  }
  statement {
    sid      = "AllowCloudWatchLogs"
    effect   = "Allow"
    actions  = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.region}:*:log-group:/aws/ec2/${var.name}-agentic*"]
  }
  statement {
    sid      = "AllowXRay"
    effect   = "Allow"
    actions  = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:PutInsightEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "agentic_policy" {
  name   = "${var.name}-agentic-policy"
  role   = aws_iam_role.agentic_role.id
  policy = data.aws_iam_policy_document.agentic_policy.json
}

resource "aws_iam_instance_profile" "agentic_profile" {
  name = "${var.name}-agentic-profile"
  role = aws_iam_role.agentic_role.name
}
