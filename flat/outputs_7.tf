# modules/data_services/outputs.tf

output "qdrant_instance_private_ip" {
  description = "The private IP address of the Qdrant EC2 instance."
  value       = aws_instance.qdrant.private_ip
}

output "secrets_manager_secret_arns" {
  value       = [for s in aws_secretsmanager_secret.this : s.arn]
  description = "ARNs of created Secrets"
}

# ADDED: A map of secret names to their ARNs for easier lookup.
output "secrets_manager_secret_arns_map" {
  value       = { for k, s in aws_secretsmanager_secret.this : k => s.arn }
  description = "Map of secret names to their ARNs"
}

output "data_services_security_group_id" {
  description = "Security Group for Redis & Qdrant"
  value       = aws_security_group.data_services_sg.id
}
