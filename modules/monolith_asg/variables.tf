# modules/monolith_asg/variables.tf

variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "instance_type" {
  type = string
}

variable "min_size" {
  type = number
}

variable "max_size" {
  type = number
}

variable "desired_capacity" {
  type = number
}

variable "assets_bucket" {
  type = string
}

variable "sqs_queue_arn" {
  type = string
}

variable "secrets_manager_secret_arn" {
  type = string
}

variable "region" {
  type    = string
  default = "eu-central-1"
}

# ADDED: New variable to optionally specify the ECR image URI for the monolith.
variable "monolith_image_uri" {
  description = "Optional full image URI for the monolith container to pull and run. If empty, no container will be launched."
  type        = string
  default     = ""
}
