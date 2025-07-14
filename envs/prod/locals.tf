locals {
  name_prefix = "${var.project}-${var.environment}-${var.tenant_id}"
}

data "aws_availability_zones" "available" {}
