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
output "fck_nat_security_group_id" {
  description = "The ID of the security group used by the fck-nat instance."
  value       = module.fck_nat.security_group_id
}
output "qdrant_efs_id" {
  description = "The ID of the EFS file system for Qdrant."
  value       = aws_efs_file_system.qdrant_storage.id
}

output "efs_security_group_id" {
  description = "The ID of the security group for the EFS mount targets."
  value       = aws_security_group.efs_sg.id
}