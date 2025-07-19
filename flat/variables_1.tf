variable "name" {
  description = "Prefix (project-env-tenant) for all RAG resources"
  type        = string
}

variable "tenant_id" {
  description = "Tenant identifier (passed to Lambdas)"
  type        = string
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "eu-central-1"
}

variable "vpc_id" {
  description = "VPC ID for RAG Lambdas"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets for VPC-enabled Lambdas"
  type        = list(string)
}

# Lambda code locations
variable "chunk_lambda_s3_bucket" {
  type = string
}

variable "chunk_lambda_s3_key" {
  type = string
}

variable "embed_lambda_s3_bucket" {
  type = string
}

variable "embed_lambda_s3_key" {
  type = string
}

variable "index_lambda_s3_bucket" {
  type = string
}

variable "index_lambda_s3_key" {
  type = string
}

variable "lambda_runtime" {
  type    = string
  default = "python3.9"
}

variable "secrets_manager_secret_arn" {
  description = "ARN of a generic Secrets Manager secret Lambda can read"
  type        = string
  default     = null
}

variable "lambda_security_group_id" {
  description = "The security group ID to assign to the VPC-enabled Lambdas."
  type        = string
}

variable "bedrock_embed_model_arn" {
  description = "The ARN of the Bedrock model to use for embeddings."
  type        = string
}

variable "qdrant_endpoint" {
  description = "The network endpoint for the Qdrant vector database."
  type        = string
}

variable "qdrant_api_key_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing the Qdrant API key."
  type        = string
}