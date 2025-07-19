# modules/ingress/main.tf

###############################################################################
# 1. API Gateway
###############################################################################
resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.name}-api"
  description = "API Gateway for secure uploads and other interactions."
}

resource "aws_api_gateway_resource" "upload" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "upload"
}

resource "aws_api_gateway_method" "upload_post" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.upload.id
  http_method   = "POST"
  authorization = "NONE" # In a real scenario, this would be linked to a Lambda Authorizer
}

###############################################################################
# 2. Generate Pre-signed URL Lambda
###############################################################################
resource "aws_iam_role" "presigned_url_lambda_role" {
  name               = "${var.name}-presigned-url-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
}

# ADDED: Standard managed policy for CloudWatch logging.
resource "aws_iam_role_policy_attachment" "lambda_logging" {
  role       = aws_iam_role.presigned_url_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# UPDATED: Inline policy with least-privilege permissions for S3 and Secrets Manager.
resource "aws_iam_role_policy" "presigned_url_lambda_policy" {
  name   = "${var.name}-presigned-url-lambda-policy"
  role   = aws_iam_role.presigned_url_lambda_role.id
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Sid      = "AllowS3Put",
        Effect   = "Allow",
        Action   = "s3:PutObject",
        Resource = "${var.priority_uploads_bucket_arn}/*"
      },
      {
        Sid      = "AllowSecretsRead",
        Effect   = "Allow",
        Action   = "secretsmanager:GetSecretValue",
        Resource = var.jwt_secret_arn
      }
    ]
  })
}

resource "aws_lambda_function" "generate_presigned_url" {
  function_name    = "${var.name}-generate-presigned-url"
  s3_bucket        = var.lambda_code_bucket
  s3_key           = "generate_presigned_url.zip" # Placeholder for your Lambda code
  handler          = "index.handler"
  runtime          = "nodejs18.x" # Example runtime
  role             = aws_iam_role.presigned_url_lambda_role.arn
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      PRIORITY_UPLOADS_BUCKET = var.priority_uploads_bucket_id
      # UPDATED: Pass the ARN of the secret, not the secret itself.
      JWT_SECRET_ARN          = var.jwt_secret_arn
    }
  }
}

###############################################################################
# 3. API Gateway Integration
###############################################################################
resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.upload.id
  http_method             = aws_api_gateway_method.upload_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.generate_presigned_url.invoke_arn
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.generate_presigned_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

###############################################################################
# 4. Common Resources
###############################################################################
data "aws_iam_policy_document" "assume_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}
