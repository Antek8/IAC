# modules/rag_pipeline/main.tf

###############################################################################
# 0 Security Group for RAG Lambdas
###############################################################################
resource "aws_security_group" "rag_lambda_sg" {
  name        = "${var.name}-lambda-sg"
  description = "No inbound; full egress so Lambdas can reach S3, SQS, Bedrock, etc."
  vpc_id      = var.vpc_id

  # No ingress blocks

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 1 S3 bucket for chunk storage
resource "aws_s3_bucket" "this" {
  bucket = "${var.name}-rag-chuncky"
  # acl has been deprecated and is now managed by aws_s3_bucket_ownership_controls
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "this" {
  depends_on = [aws_s3_bucket_ownership_controls.this]
  bucket     = aws_s3_bucket.this.id
  acl        = "private"
}


resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

# DEPRECATED 'server_side_encryption_configuration' is replaced by this resource
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 2 SQS + DLQ
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-rag-dlq"
  message_retention_seconds = 1209600 # 14 days
}

resource "aws_sqs_queue" "main" {
  name                       = "${var.name}-rag-queue"
  visibility_timeout_seconds = 60

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })
}

# 3 IAM for Lambdas
data "aws_iam_policy_document" "assume_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.name}-rag-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid       = "AllowS3"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
  }
  statement {
    sid       = "AllowSQS"
    actions   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.main.arn]
  }
  statement {
    sid       = "AllowSecrets"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.secrets_manager_secret_arn]
  }
  statement {
    sid       = "AllowLogs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.region}:*:log-group:/aws/lambda/${var.name}-*"]
  }
  statement {
    sid       = "AllowXRay"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
  # Add VPC permissions for Lambda
  statement {
    sid = "AllowVPC"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "${var.name}-rag-lambda-policy"
  # CORRECTED: The role was named 'lambda', not 'lambda_role'
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_policy.json
}

# 5 Define each Lambda
resource "aws_lambda_function" "chunk" {
  function_name = "${var.name}-chunk"
  s3_bucket     = var.chunk_lambda_s3_bucket
  s3_key        = var.chunk_lambda_s3_key
  handler       = "chunk.lambda_handler"
  runtime       = var.lambda_runtime
  role          = aws_iam_role.lambda.arn
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.rag_lambda_sg.id]
  }

  environment {
    variables = {
      BUCKET    = aws_s3_bucket.this.bucket
      QUEUE_URL = aws_sqs_queue.main.id
      TENANT_ID = var.tenant_id
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "embed" {
  function_name = "${var.name}-embed"
  s3_bucket     = var.embed_lambda_s3_bucket
  s3_key        = var.embed_lambda_s3_key
  handler       = "embed_processor.lambda_handler"
  runtime       = var.lambda_runtime
  role          = aws_iam_role.lambda.arn
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.rag_lambda_sg.id]
  }

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.main.id
      TENANT_ID = var.tenant_id
    }
  }

  tracing_config {
    mode = "Active"
  }
}

resource "aws_lambda_function" "index" {
  function_name = "${var.name}-index"
  s3_bucket     = var.index_lambda_s3_bucket
  s3_key        = var.index_lambda_s3_key
  handler       = "index_lambda.lambda_handler"
  runtime       = var.lambda_runtime
  role          = aws_iam_role.lambda.arn
  memory_size   = var.lambda_memory_size
  timeout       = var.lambda_timeout

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.rag_lambda_sg.id]
  }

  environment {
    variables = {
      TENANT_ID = var.tenant_id
    }
  }

  tracing_config {
    mode = "Active"
  }
}
