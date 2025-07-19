# modules/rag_pipeline/outputs.tf

# FIXED: These outputs are now valid again after restoring the resources in main.tf
output "bucket_name" {
  description = "Name of S3 bucket for RAG storage"
  value       = aws_s3_bucket.this.bucket
}

output "queue_url" {
  description = "URL of main RAG SQS queue"
  value       = aws_sqs_queue.main.id
}

output "queue_arn" {
  description = "ARN of main RAG SQS queue"
  value       = aws_sqs_queue.main.arn
}

output "dlq_arn" {
  description = "ARN of dead-letter queue"
  value       = aws_sqs_queue.dlq.arn
}
