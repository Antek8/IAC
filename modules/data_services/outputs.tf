# modules/data_services/outputs.tf

output "redis_primary_endpoint" {
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
  description = "Redis endpoint"
}

output "qdrant_cluster_arn" {
  value       = aws_ecs_cluster.qdrant.arn
  description = "ECS Cluster ARN for Qdrant"
}

output "qdrant_service_name" {
  value       = aws_ecs_service.qdrant.name
  description = "ECS Service name for Qdrant"
}

output "secrets_manager_secret_arns" {
  value       = [for s in aws_secretsmanager_secret.this : s.arn]
  description = "ARNs of created Secrets"
}

output "data_services_security_group_id" {
  description = "Security Group for Redis & Qdrant"
  value       = aws_security_group.data_services_sg.id
}
