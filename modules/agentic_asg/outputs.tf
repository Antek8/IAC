# modules/agentic_asg/outputs.tf

output "asg_name" {
  description = "Name of the Agentic Auto Scaling Group"
  value       = aws_autoscaling_group.agentic_asg.name
}

output "security_group_id" {
  description = "Security Group ID for Agentic instances"
  value       = aws_security_group.agentic_sg.id
}

# ADDED: Output for the new ECR repository URI.
output "agentic_ecr_uri" {
  description = "The URI of the ECR repository for the agentic container."
  value       = aws_ecr_repository.agentic.repository_url
}
