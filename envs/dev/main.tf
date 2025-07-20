# envs/dev/main.tf
resource "aws_s3_object" "generate_presigned_url_lambda_code" {
  bucket = aws_s3_bucket.lambda_code.id
  key    = "generate_presigned_url.zip" # This should match the key in your ingress module
  source = data.archive_file.dummy_lambda_zip.output_path
  etag   = filemd5(data.archive_file.dummy_lambda_zip.output_path)
}

resource "aws_s3_object" "confluence_checker_lambda_code" {
  bucket = aws_s3_bucket.lambda_code.id
  key    = var.confluence_checker_lambda_s3_key
  source = data.archive_file.dummy_lambda_zip.output_path
  etag   = filemd5(data.archive_file.dummy_lambda_zip.output_path)
}

resource "aws_iam_role" "scheduler_role" {
  name = "${local.name_prefix}-scheduler-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "scheduler.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_scheduler_schedule" "confluence_sync" {
  name       = "${local.name_prefix}-confluence-sync-schedule"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = var.confluence_sync_schedule

  target {
    arn      = module.rag_pipeline.confluence_checker_lambda_arn
    role_arn = aws_iam_role.scheduler_role.arn
  }
}
resource "aws_iam_role_policy" "scheduler_policy" {
  name = "${local.name_prefix}-scheduler-policy"
  role = aws_iam_role.scheduler_role.id
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = "lambda:InvokeFunction",
      Resource = module.rag_pipeline.confluence_checker_lambda_arn
    }]
  })
}
resource "aws_s3_bucket" "lambda_code" {
  bucket = var.lambda_code_bucket_name
}

resource "aws_s3_bucket" "monolith_assets" {
  bucket = "${local.name_prefix}-monolith-assets"
}

data "archive_file" "dummy_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/dummy_lambda.zip"

  source {
    content  = "exports.handler = async (event) => {};"
    filename = "index.js"
  }
}

resource "aws_s3_object" "chunk_lambda_code" {
  bucket = aws_s3_bucket.lambda_code.id
  key    = var.chunk_lambda_s3_key
  source = data.archive_file.dummy_lambda_zip.output_path
  etag   = filemd5(data.archive_file.dummy_lambda_zip.output_path)
}

resource "aws_s3_object" "embed_lambda_code" {
  bucket = aws_s3_bucket.lambda_code.id
  key    = var.embed_lambda_s3_key
  source = data.archive_file.dummy_lambda_zip.output_path
  etag   = filemd5(data.archive_file.dummy_lambda_zip.output_path)
}

module "vpc" {
  source                   = "../../modules/vpc"
  name                     = local.name_prefix
  cidr                     = var.vpc_cidr
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_rag_subnet_cidrs = var.private_rag_subnet_cidrs
  region                   = var.region
}

module "ingress" {
  source                      = "../../modules/ingress"
  name                        = local.name_prefix
  priority_uploads_bucket_id  = module.rag_pipeline.priority_uploads_bucket_id
  priority_uploads_bucket_arn = module.rag_pipeline.priority_uploads_bucket_arn
  lambda_code_bucket          = aws_s3_bucket.lambda_code.id
  jwt_secret_arn              = module.data_services.secrets_manager_secret_arns_map["jwt_secret"]

  vpc_id                      = module.vpc.vpc_id
  public_subnet_ids           = module.vpc.public_subnet_ids
  alb_security_group_id       = module.vpc.alb_security_group_id
  acm_certificate_arn         = var.acm_certificate_arn # You'll need to add this variable

  depends_on = [
    aws_s3_object.generate_presigned_url_lambda_code
  ]
}

module "rag_pipeline" {
  source                 = "../../modules/rag_pipeline"
  name                   = local.name_prefix
  tenant_id              = var.tenant_id
  region                 = var.region
  private_subnet_ids     = module.vpc.private_rag_subnet_ids
  vpc_id                 = module.vpc.vpc_id
  chunk_lambda_s3_bucket = aws_s3_bucket.lambda_code.id
  chunk_lambda_s3_key    = var.chunk_lambda_s3_key

  embed_lambda_s3_bucket = aws_s3_bucket.lambda_code.id
  embed_lambda_s3_key    = var.embed_lambda_s3_key
  bedrock_embed_model_arn  = var.bedrock_embed_model_arn
  qdrant_api_key_secret_arn = module.data_services.secrets_manager_secret_arns_map["qdrant_api_key"]
  confluence_checker_lambda_s3_key = var.confluence_checker_lambda_s3_key
  confluence_api_key_secret_arn    = module.data_services.secrets_manager_secret_arns_map["confluence_api_key"]

  lambda_security_group_id  = module.vpc.rag_lambda_security_group_id
  
  depends_on = [
    aws_s3_object.chunk_lambda_code,
    aws_s3_object.embed_lambda_code,
    aws_s3_object.generate_presigned_url_lambda_code,
    aws_s3_object.confluence_checker_lambda_code
  ]
}

module "monolith_asg" {
  source                     = "../../modules/monolith_asg"
  name                       = "${local.name_prefix}-web"
  vpc_id                     = module.vpc.vpc_id
  private_subnet_ids         = module.vpc.private_app_subnet_ids
  instance_type              = var.web_instance_type
  min_size                   = var.web_min_size
  max_size                   = var.web_max_size
  desired_capacity           = var.web_desired_capacity
  assets_bucket              = aws_s3_bucket.monolith_assets.bucket
  sqs_queue_arn              = module.rag_pipeline.high_priority_queue_arn
  secrets_manager_secret_arn = module.data_services.secrets_manager_secret_arns_map["db_password"]
  region                     = var.region
  monolith_image_uri         = var.monolith_image_uri
  tenant_id                  = var.tenant_id
  target_group_arn      = module.ingress.monolith_target_group_arn
  alb_security_group_id = module.vpc.alb_security_group_id

}

module "agentic_asg" {
  source                            = "../../modules/agentic_asg"
  name                              = "${local.name_prefix}-agentic"
  vpc_id                            = module.vpc.vpc_id
  private_subnet_ids                = module.vpc.private_app_subnet_ids
  allowed_source_security_group_ids = [module.monolith_asg.security_group_id]
  instance_type                     = var.agentic_instance_type
  min_size                          = var.agentic_min_size
  max_size                          = var.agentic_max_size
  desired_capacity                  = var.agentic_desired_capacity
  s3_bucket_name                    = module.rag_pipeline.rag_chunks_bucket_name
  sqs_queue_url                     = module.rag_pipeline.high_priority_queue_url
  sqs_queue_arn                     = module.rag_pipeline.high_priority_queue_arn
  secrets_manager_secret_arn        = module.data_services.secrets_manager_secret_arns_map["db_password"]
  region                            = var.region
  agentic_image_uri                 = var.agentic_image_uri
  tenant_id                         = var.tenant_id

}

module "data_services" {
  source               = "../../modules/data_services"
  name                 = local.name_prefix
  tenant_id            = var.tenant_id
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_app_subnet_ids
  region               = var.region
  qdrant_instance_type = var.qdrant_instance_type
  
  secrets = {
    "db_password"        = "changeme123"
    "qdrant_api_key"     = var.qdrant_api_key
    "jwt_secret"         = var.jwt_secret
    "confluence_api_key" = "your-confluence-api-key" # Add this line
  }
}

module "iam" {
  source                     = "../../modules/iam"
  name                       = local.name_prefix
  region                     = var.region
  s3_bucket_name             = module.rag_pipeline.rag_chunks_bucket_name
  sqs_queue_arn              = module.rag_pipeline.high_priority_queue_arn
  secrets_manager_secret_arn = module.data_services.secrets_manager_secret_arns_map["db_password"]
}

resource "aws_security_group_rule" "agentic_to_data_qdrant" {
  type                     = "ingress"
  from_port                = 6333
  to_port                  = 6333
  protocol                 = "tcp"
  source_security_group_id = module.agentic_asg.security_group_id
  security_group_id        = module.data_services.data_services_security_group_id
  description              = "Allow Agentic ASG to Qdrant"
}
