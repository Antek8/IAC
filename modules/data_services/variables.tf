# modules/data_services/variables.tf

variable "name" {
  description = "Prefix (project-env-tenant) for data services"
  type        = string
}

variable "tenant_id" {
  description = "Tenant identifier"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets for ElastiCache & ECS"
  type        = list(string)
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

# ADDED: Variable for the Qdrant instance type.
variable "qdrant_instance_type" {
  description = "Instance type for the Qdrant EC2 instance."
  type        = string
  default     = "t4g.small"
}

variable "qdrant_container_image" {
  description = "Docker image for Qdrant"
  type        = string
  default     = "qdrant/qdrant:latest"
}

variable "secrets" {
  description = "Map of secret names ⇒ initial values (optional)"
  type        = map(string)
  default     = {}
}
variable "qdrant_min_size" {
  description = "Minimum number of instances in the Qdrant ASG."
  type        = number
  default     = 1
}

variable "qdrant_max_size" {
  description = "Maximum number of instances in the Qdrant ASG."
  type        = number
  default     = 2
}

variable "qdrant_desired_capacity" {
  description = "Desired number of instances in the Qdrant ASG."
  type        = number
  default     = 1
}
variable "qdrant_efs_id" {
  description = "The ID of the EFS file system for Qdrant."
  type        = string
}

variable "efs_security_group_id" {
  description = "The ID of the security group for the EFS mount targets."
  type        = string
}