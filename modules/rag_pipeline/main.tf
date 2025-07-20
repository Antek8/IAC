# modules/rag_pipeline/main.tf

###############################################################################
# 1. S3 Buckets & SQS Queues
###############################################################################

# This is the new bucket for direct user uploads.
resource "aws_s3_bucket" "priority_uploads" {
  bucket = "${var.name}-priority-uploads"
}

resource "aws_s3_bucket_cors_configuration" "priority_uploads_cors" {
  bucket = aws_s3_bucket.priority_uploads.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["*"] # In production, restrict this to your domain
    expose_headers  = ["ETag"]
  }
}

# This existing bucket is now for processed chunks only.
resource "aws_s3_bucket" "rag_chunks" {
  bucket = "${var.name}-rag-chunks"
}

resource "aws_sqs_queue" "dlq" {
  name = "${var.name}-rag-dlq"
}

resource "aws_sqs_queue" "high_priority_queue" {
  name = "${var.name}-high-priority-queue"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })
}

# S3 event notification to trigger the SQS queue on new uploads.
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.priority_uploads.id

  queue {
    queue_arn     = aws_sqs_queue.high_priority_queue.arn
    events        = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sqs_queue_policy.high_priority_queue_policy]
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
        Sid      = "S3ReadUploads",
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:GetObjectTagging"],
        Resource = "${aws_s3_bucket.priority_uploads.arn}/*"
      },
      {
        Sid      = "S3PutChunks",
        Effect   = "Allow",
        Action   = ["s3:PutObject", "s3:PutObjectTagging"],
        Resource = "${aws_s3_bucket.rag_chunks.arn}/*"
      },
      {
        Sid    = "SQSRead",
        Effect = "Allow",
        Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"],

        Resource = [
          aws_sqs_queue.high_priority_queue.arn,
          aws_sqs_queue.low_priority_queue.arn
        ]
      }
    ]
  })
}

resource "aws_lambda_function" "chunk" {
  function_name = "${var.name}-chunk"
  s3_bucket     = var.chunk_lambda_s3_bucket
  s3_key        = var.chunk_lambda_s3_key
  handler       = "chunk.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.chunk_lambda_role.arn
  timeout       = 15
  memory_size   = 256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }
}

resource "aws_lambda_event_source_mapping" "chunk_trigger" {
  event_source_arn = aws_sqs_queue.high_priority_queue.arn
  function_name    = aws_lambda_function.chunk.arn
}
resource "aws_sqs_queue_policy" "high_priority_queue_policy" {
  queue_url = aws_sqs_queue.high_priority_queue.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { Service = "s3.amazonaws.com" },
        Action    = "sqs:SendMessage",
        Resource  = aws_sqs_queue.high_priority_queue.arn,
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_s3_bucket.priority_uploads.arn }
        }
      }
    ]
  })
}
###############################################################################
# 3. Embed & Index Lambda
###############################################################################
resource "aws_iam_role" "embed_index_lambda_role" {
  name               = "${var.name}-embed-index-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
}

resource "aws_iam_role_policy_attachment" "embed_index_vpc_access" {
  role       = aws_iam_role.embed_index_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# UPDATED: Inline policy with the exact permissions required for the Embed & Index Lambda.
resource "aws_iam_role_policy" "embed_index_lambda_policy" {
  name = "${var.name}-embed-index-lambda-policy"
  role = aws_iam_role.embed_index_lambda_role.id
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Sid      = "S3ReadChunks",
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:GetObjectTagging"],
        Resource = "${aws_s3_bucket.rag_chunks.arn}/*"
      },
      {
        Sid      = "BedrockInvoke",
        Effect   = "Allow",
        Action   = "bedrock:InvokeModel",
        Resource = var.bedrock_embed_model_arn
      },
      {
        Sid      = "SecretsManagerRead",
        Effect   = "Allow",
        Action   = "secretsmanager:GetSecretValue",
        Resource = var.qdrant_api_key_secret_arn
      }
    ]
  })
}

resource "aws_lambda_function" "embed_and_index" {
  function_name = "${var.name}-embed-and-index"
  s3_bucket     = var.embed_lambda_s3_bucket
  s3_key        = var.embed_lambda_s3_key
  handler       = "embed_index.handler"
  runtime       = "python3.9"
  role          = aws_iam_role.embed_index_lambda_role.arn
  timeout       = 30
  memory_size   = 512

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }
}

resource "aws_s3_bucket_notification" "chunk_notification" {
  bucket = aws_s3_bucket.rag_chunks.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.embed_and_index.arn
    events              = ["s3:ObjectCreated:*"]
  }
  depends_on = [aws_lambda_permission.allow_s3_invoke_embed_index]

}
resource "aws_lambda_permission" "allow_s3_invoke_embed_index" {
  statement_id  = "AllowS3InvokeEmbedAndIndexLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.embed_and_index.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.rag_chunks.arn
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

resource "aws_sqs_queue" "low_priority_queue" {
  name = "${var.name}-rag-queue" # This is the original name you wanted

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_iam_role" "confluence_checker_lambda_role" {
  name               = "${var.name}-confluence-checker-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
}

resource "aws_iam_role_policy_attachment" "confluence_checker_vpc_access" {
  role       = aws_iam_role.confluence_checker_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "confluence_checker_lambda_policy" {
  name = "${var.name}-confluence-checker-lambda-policy"
  role = aws_iam_role.confluence_checker_lambda_role.id
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Sid      = "SQSSendMessage",
        Effect   = "Allow",
        Action   = "sqs:SendMessage",
        Resource = aws_sqs_queue.low_priority_queue.arn
      },
      {
        Sid      = "SecretsManagerRead",
        Effect   = "Allow",
        Action   = "secretsmanager:GetSecretValue",
        Resource = var.confluence_api_key_secret_arn
      }
    ]
  })
}

resource "aws_lambda_function" "confluence_checker" {
  function_name = "${var.name}-confluence-checker"
  s3_bucket     = var.chunk_lambda_s3_bucket # Assuming same bucket for all lambdas
  s3_key        = var.confluence_checker_lambda_s3_key
  handler       = "confluence_checker.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.confluence_checker_lambda_role.arn
  timeout       = 300 # Increased timeout for potentially long-running sync checks
  memory_size   = 256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }
}

resource "aws_lambda_event_source_mapping" "chunk_trigger_low_priority" {
  event_source_arn = aws_sqs_queue.low_priority_queue.arn
  function_name    = aws_lambda_function.chunk.arn
}