# envs/dev/backend.tf
terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
    # ADDED: The 'random' provider is needed for the secret name fix.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
  backend "s3" {
    bucket         = "kane-backend-bucket"
    key            = "dev/terraform.tfstate"
    region         = "eu-central-1" # Hardcoded region
    dynamodb_table = "kane-terraform-db"
    encrypt        = true
  }
}