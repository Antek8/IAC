# envs/prod/variables.tf

variable "project" {
  type    = string
  default = "myapp"
}

variable "environment" {
  type    = string
  default = "prod"
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

# NAT scheduling (optional tweak)
variable "nat_on_time" {
  type    = string
  default = "cron(0 7 * * ? *)"
}

variable "nat_off_time" {
  type    = string
  default = "cron(0 19 * * ? *)"
}

# Web ASG sizing
variable "web_instance_type" {
  type    = string
  default = "t3.medium"
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
variable "chunk_lambda_s3_bucket" {
  type    = string
  default = "myapp-lambda-code"
}

variable "chunk_lambda_s3_key" {
  type    = string
  default = "chunk.zip"
}

variable "embed_lambda_s3_bucket" {
  type    = string
  default = "myapp-lambda-code"
}

variable "embed_lambda_s3_key" {
  type    = string
  default = "embed.zip"
}

variable "index_lambda_s3_bucket" {
  type    = string
  default = "myapp-lambda-code"
}

variable "index_lambda_s3_key" {
  type    = string
  default = "index.zip"
}

# Agentic ASG sizing
variable "agentic_instance_type" {
  type    = string
  default = "t3.medium"
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
