# modules/frontend_asg/outputs.tf

output "asg_name" {
  description = "Name of the frontend Auto Scaling Group"
  value       = aws_autoscaling_group.frontend_asg.name
}

output "security_group_id" {
  description = "Security Group ID for frontend instances"
  value       = aws_security_group.frontend.id
}

# ADDED: Output for the new ECR repository URI.
output "frontend_ecr_uri" {
  description = "The URI of the ECR repository for the frontend container."
  value       = aws_ecr_repository.frontend.repository_url
}
