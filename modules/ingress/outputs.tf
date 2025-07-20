# modules/ingress/outputs.tf

output "api_gateway_invoke_url" {
  description = "The invoke URL for the API Gateway."
  value       = aws_api_gateway_rest_api.this.execution_arn
}
output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer."
  value       = aws_lb.this.dns_name
}
output "monolith_target_group_arn" {
  description = "The ARN of the monolith target group."
  value       = aws_lb_target_group.monolith.arn
}