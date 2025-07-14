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

variable "lambda_memory_size" {
  type    = number
  default = 512
}

variable "lambda_timeout" {
  type    = number
  default = 60
}

variable "secrets_manager_secret_arn" {
  description = "ARN of Secrets Manager secret Lambda will read"
  type        = string
}
