# modules/rag_pipeline/main.tf

###############################################################################
# 1. S3 Bucket & SQS Queues
###############################################################################

resource "aws_s3_bucket" "this" {
  bucket = "${var.name}-rag-chuncky"
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
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


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

###############################################################################
# 2. Chunk-Splitter Lambda
###############################################################################

resource "aws_iam_role" "chunk_lambda_role" {
  name               = "${var.name}-chunk-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
}

resource "aws_iam_role_policy_attachment" "chunk_vpc_access" {
  role       = aws_iam_role.chunk_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "chunk_lambda_policy" {
  name   = "${var.name}-chunk-lambda-policy"
  role   = aws_iam_role.chunk_lambda_role.id
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Sid    = "S3GetObject",
        Effect = "Allow",
        Action = "s3:GetObject",
        Resource = "${aws_s3_bucket.this.arn}/*"
      },
      {
        Sid    = "SQSSendMessage",
        Effect = "Allow",
        Action = "sqs:SendMessage",
        Resource = aws_sqs_queue.main.arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "chunk_lambda_logs" {
  name              = "/aws/lambda/${var.name}-chunk"
  retention_in_days = 7
}

resource "aws_lambda_function" "chunk" {
  function_name    = "${var.name}-chunk"
  s3_bucket        = var.chunk_lambda_s3_bucket
  s3_key           = var.chunk_lambda_s3_key
  handler          = "chunk.lambda_handler"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.chunk_lambda_role.arn
  timeout          = 15
  memory_size      = 256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      SOURCE_BUCKET   = aws_s3_bucket.this.id
      CHUNK_QUEUE_URL = aws_sqs_queue.main.id
      CHUNK_SIZE      = "1024" # Example value
    }
  }

  tracing_config {
    mode = "Active" # Enable X-Ray Tracing as requested
  }

  depends_on = [aws_cloudwatch_log_group.chunk_lambda_logs]
}


###############################################################################
# 3. Embedding Lambda
###############################################################################

resource "aws_iam_role" "embed_lambda_role" {
  name               = "${var.name}-embed-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
}

resource "aws_iam_role_policy_attachment" "embed_vpc_access" {
  role       = aws_iam_role.embed_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "embed_lambda_policy" {
  name   = "${var.name}-embed-lambda-policy"
  role   = aws_iam_role.embed_lambda_role.id
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Sid      = "BedrockInvoke",
        Effect   = "Allow",
        Action   = "bedrock:InvokeModel",
        Resource = var.bedrock_embed_model_arn
      },
      {
        Sid      = "S3Access",
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:PutObject"],
        Resource = "${aws_s3_bucket.this.arn}/*"
      },
      {
        Sid      = "SQSRead",
        Effect   = "Allow",
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"],
        Resource = aws_sqs_queue.main.arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "embed_lambda_logs" {
  name              = "/aws/lambda/${var.name}-embed"
  retention_in_days = 7
}

resource "aws_lambda_function" "embed" {
  function_name    = "${var.name}-embed"
  s3_bucket        = var.embed_lambda_s3_bucket
  s3_key           = var.embed_lambda_s3_key
  handler          = "embed_processor.lambda_handler"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.embed_lambda_role.arn
  timeout          = 30
  memory_size      = 512

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      EMBED_BUCKET            = aws_s3_bucket.this.id
      BEDROCK_EMBED_MODEL_ARN = var.bedrock_embed_model_arn
    }
  }

  tracing_config {
    mode = "PassThrough"
  }

  depends_on = [aws_cloudwatch_log_group.embed_lambda_logs]
}


###############################################################################
# 4. Indexer Lambda
###############################################################################

resource "aws_iam_role" "index_lambda_role" {
  name               = "${var.name}-index-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
}

resource "aws_iam_role_policy_attachment" "index_vpc_access" {
  role       = aws_iam_role.index_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "index_secrets_policy" {
  name = "${var.name}-index-secrets-policy"
  role = aws_iam_role.index_lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowSecrets",
        Effect = "Allow",
        Action = "secretsmanager:GetSecretValue",
        Resource = var.qdrant_api_key_secret_arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "index_lambda_logs" {
  name              = "/aws/lambda/${var.name}-index"
  retention_in_days = 7
}

resource "aws_lambda_function" "index" {
  function_name    = "${var.name}-index"
  s3_bucket        = var.index_lambda_s3_bucket
  s3_key           = var.index_lambda_s3_key
  handler          = "index_lambda.lambda_handler"
  runtime          = var.lambda_runtime
  role             = aws_iam_role.index_lambda_role.arn
  timeout          = 15
  memory_size      = 256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      QDRANT_ENDPOINT    = var.qdrant_endpoint
      API_KEY_SECRET_ARN = var.qdrant_api_key_secret_arn
    }
  }

  tracing_config {
    mode = "PassThrough"
  }

  depends_on = [aws_cloudwatch_log_group.index_lambda_logs]
}

# Common data source used by all Lambda roles
data "aws_iam_policy_document" "assume_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}
