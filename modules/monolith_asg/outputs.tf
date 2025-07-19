# modules/monolith_asg/outputs.tf

output "asg_name" {
  description = "Name of the Monolith Auto Scaling Group"
  value       = aws_autoscaling_group.monolith_asg.name
}

output "security_group_id" {
  description = "Security Group ID for Monolith instances"
  value       = aws_security_group.monolith.id
}

# ADDED: Output for the new ECR repository URI.
output "monolith_ecr_uri" {
  description = "The URI of the ECR repository for the monolith container."
  value       = aws_ecr_repository.monolith.repository_url
}
