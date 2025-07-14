# envs/dev/locals.tf

locals {
  # FIXED: Enforce lowercase on the name_prefix to comply with AWS naming
  # conventions for resources like S3 buckets and ECR repositories.
  name_prefix = lower("${var.project}-${var.environment}-${var.tenant_id}")
}

data "aws_availability_zones" "azs" {}
