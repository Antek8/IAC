# modules/agentic_asg/outputs.tf
output "asg_name" {
  description = "Name of the Agentic Auto Scaling Group"
  value       = aws_autoscaling_group.agentic_asg.name
}

output "security_group_id" {
  description = "Security Group ID for Agentic instances"
  value       = aws_security_group.agentic_sg.id
}
