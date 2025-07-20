# modules/vpc/outputs.tf

output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  value = aws_subnet.private_app[*].id
}

output "private_rag_subnet_ids" {
  value = aws_subnet.private_rag[*].id
}
output "rag_lambda_security_group_id" {
  description = "The ID of the security group for the RAG pipeline Lambdas."
  value       = aws_security_group.rag_lambda_sg.id
}
output "alb_security_group_id" {
  description = "The ID of the security group for the Application Load Balancer."
  value       = aws_security_group.alb_sg.id
}