# modules/frontend_asg/variables.tf

variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
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

variable "frontend_image_uri" {
  description = "Optional full image URI for the frontend container to pull and run. If empty, no container will be launched."
  type        = string
  default     = ""
}
variable "tenant_id" {
  description = "The tenant identifier, used for naming and resource tagging."
  type        = string
}
variable "target_group_arn" {
  description = "The ARN of the ALB target group to attach the ASG to."
  type        = string
}

variable "alb_security_group_id" {
  description = "The ID of the ALB's security group to allow ingress traffic from."
  type        = string
}

variable "jump_host_security_group_id" {
  description = "The security group ID of the jump host to allow SSH from."
  type        = string
}
variable "project" {
  description = "The project name, used for resource tagging and naming."
  type        = string
}