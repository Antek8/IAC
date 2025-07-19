# envs/dev/provider.tf
provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      Tenant      = var.tenant_id
    }
  }
}
