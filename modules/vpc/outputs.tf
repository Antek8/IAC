output "vpc_id"                 { value = aws_vpc.this.id }
output "public_subnet_ids"      { value = aws_subnet.public[*].id }
output "private_app_subnet_ids" { value = aws_subnet.private_app[*].id }
output "private_rag_subnet_ids" { value = aws_subnet.private_rag[*].id }

