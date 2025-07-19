# modules/agentic_asg/variables.tf

variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "allowed_source_security_group_ids" {
  type = list(string)
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 2
}

variable "desired_capacity" {
  type    = number
  default = 1
}

variable "s3_bucket_name" {
  type = string
}

variable "sqs_queue_arn" {
  type = string
}

variable "sqs_queue_url" {
  type = string
}

variable "secrets_manager_secret_arn" {
  type = string
}

variable "region" {
  type    = string
  default = "eu-central-1"
}

# ADDED: New variable to optionally specify the ECR image URI.
variable "agentic_image_uri" {
  description = "Optional full image URI for the agentic container to pull and run. If empty, no container will be launched."
  type        = string
  default     = ""
}
