# envs/dev/variables.tf

variable "project" {
  type    = string
  default = "myapp"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "tenant_id" {
  type    = string
  default = "T001"
}

variable "region" {
  type    = string
  default = "eu-central-1"
}

# VPC
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_rag_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.21.0/24", "10.0.22.0/24"]
}

# Web ASG sizing
variable "web_instance_type" {
  description = "Instance type for the monolith web server."
  type        = string
  default     = "t4g.micro"
}

variable "web_min_size" {
  type    = number
  default = 1
}

variable "web_max_size" {
  type    = number
  default = 2
}

variable "web_desired_capacity" {
  type    = number
  default = 1
}

# RAG code locations
variable "lambda_code_bucket_name" {
  description = "The name of the S3 bucket for Lambda function code."
  type        = string
  default     = "myapp-lambda-code-dev"
}

variable "chunk_lambda_s3_key" {
  type    = string
  default = "chunk.zip"
}

variable "index_lambda_s3_key" {
  type    = string
  default = "index.zip"
}

# Agentic ASG sizing
variable "agentic_instance_type" {
  description = "Instance type for the agentic logic server."
  type        = string
  default     = "t4g.micro"
}

variable "agentic_min_size" {
  type    = number
  default = 1
}

variable "agentic_max_size" {
  type    = number
  default = 2
}

variable "agentic_desired_capacity" {
  type    = number
  default = 1
}

variable "qdrant_instance_type" {
  description = "Instance type for the Qdrant EC2 instance."
  type        = string
  default     = "t4g.micro"
}

variable "monolith_image_uri" {
  description = "Optional: The full URI of the monolith Docker image in ECR. Leave empty to skip."
  type        = string
  default     = ""
}

variable "agentic_image_uri" {
  description = "Optional: The full URI of the agentic Docker image in ECR. Leave empty to skip."
  type        = string
  default     = ""
}


variable "qdrant_api_key" {
  description = "The API key for the Qdrant vector database."
  type        = string
  sensitive   = true
  default     = "please-change-this-insecure-default-key"
}

variable "jwt_secret" {
  description = "A secret key used for signing JWTs for the ContextToken."
  type        = string
  sensitive   = true
  default     = "a-very-insecure-default-secret-for-dev"
}

variable "bedrock_embed_model_arn" {
  description = "The ARN of the Bedrock model to use for embeddings."
  type        = string
  default     = "arn:aws:bedrock:eu-central-1::foundation-model/amazon.titan-embed-text-v1"
}
variable "embed_lambda_s3_key" {
  type    = string
  default = "embed.zip"
}

variable "confluence_checker_lambda_s3_key" {
  description = "The S3 key for the Confluence checker lambda function code."
  type        = string
  default     = "confluence_checker.zip"
}

variable "confluence_sync_schedule" {
  description = "The cron expression for the Confluence sync schedule."
  type        = string
  default     = "cron(0 12 * * ? *)" # Once a day at noon UTC
}