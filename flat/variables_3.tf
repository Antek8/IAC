# modules/iam/variables.tf

# ADDED: These variables were being used but were not declared.
variable "name" {
  description = "A name prefix for the IAM resources."
  type        = string
}

variable "s3_bucket_name" {
  description = "The name of the S3 bucket for which to grant permissions."
  type        = string
}

variable "sqs_queue_arn" {
  description = "The ARN of the SQS queue for which to grant permissions."
  type        = string
}

variable "secrets_manager_secret_arn" {
  description = "The ARN of the Secrets Manager secret to grant access to."
  type        = string
}

variable "region" {
  description = "The AWS region where resources are deployed."
  type        = string
}
