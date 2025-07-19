# modules/ingress/variables.tf

variable "name" {
  description = "A name prefix for all resources."
  type        = string
}

variable "priority_uploads_bucket_id" {
  description = "The ID of the S3 bucket for priority file uploads."
  type        = string
}

variable "priority_uploads_bucket_arn" {
  description = "The ARN of the S3 bucket for priority file uploads."
  type        = string
}

variable "lambda_code_bucket" {
  description = "The S3 bucket containing the Lambda function code."
  type        = string
}

# UPDATED: Changed from passing the raw secret to passing its secure ARN.
variable "jwt_secret_arn" {
  description = "The ARN of the Secrets Manager secret for the JWT key."
  type        = string
  sensitive   = true
}
