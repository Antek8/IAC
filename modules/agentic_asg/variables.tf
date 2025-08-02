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
  default = "t4g.small"
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 4
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

variable "agentic_image_uri" {
  description = "Optional full image URI for the agentic container to pull and run. If empty, no container will be launched."
  type        = string
  default     = ""
}

variable "tenant_id" {
  description = "The tenant identifier, used for naming and resource tagging."
  type        = string
}

variable "deploy_key_secret_arn" {
  description = "The ARN of the Secrets Manager secret for the GitHub deploy key."
  type        = string
}
variable "jump_host_security_group_id" {
  description = "The security group ID of the jump host to allow SSH from."
  type        = string
}
