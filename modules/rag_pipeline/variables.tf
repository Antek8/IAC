# modules/rag_pipeline/variables.tf

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
  description = "The S3 bucket for the embed lambda function code."
  type        = string
}

variable "embed_lambda_s3_key" {
  description = "The S3 key for the embed lambda function code."
  type        = string
}

variable "lambda_security_group_id" {
  description = "The security group ID to assign to the VPC-enabled Lambdas."
  type        = string
}

variable "bedrock_embed_model_arn" {
  description = "The ARN of the Bedrock model to use for embeddings."
  type        = string
}

# ADDED: Variable for the Qdrant API key secret ARN.
variable "qdrant_api_key_secret_arn" {
  description = "The ARN of the Secrets Manager secret containing the Qdrant API key."
  type        = string
}

variable "confluence_checker_lambda_s3_key" {
  description = "The S3 key for the Confluence checker lambda function code."
  type        = string
}

variable "confluence_api_key_secret_arn" {
  description = "The ARN of the Secrets Manager secret for the Confluence API key."
  type        = string
}