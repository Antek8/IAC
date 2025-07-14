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

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_num_clusters" {
  description = "Number of Redis nodes"
  type        = number
  default     = 1
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
