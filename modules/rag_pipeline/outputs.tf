# modules/rag_pipeline/outputs.tf

output "rag_chunks_bucket_name" {
  description = "Name of S3 bucket for processed RAG chunks"
  value       = aws_s3_bucket.rag_chunks.bucket
}

output "priority_uploads_bucket_id" {
  description = "ID of the S3 bucket for priority uploads"
  value       = aws_s3_bucket.priority_uploads.id
}

output "priority_uploads_bucket_arn" {
  description = "ARN of the S3 bucket for priority uploads"
  value       = aws_s3_bucket.priority_uploads.arn
}

output "high_priority_queue_url" {
  description = "URL of main RAG SQS queue"
  value       = aws_sqs_queue.high_priority_queue.id
}

output "high_priority_queue_arn" {
  description = "ARN of main RAG SQS queue"
  value       = aws_sqs_queue.high_priority_queue.arn
}

# FIXED: The dlq resource is now correctly defined in main.tf, so this output is valid.
output "dlq_arn" {
  description = "ARN of dead-letter queue"
  value       = aws_sqs_queue.dlq.arn
}
