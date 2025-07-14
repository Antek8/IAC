# envs/prod/main.tf

module "vpc" {
  source                   = "../../modules/vpc"
  name                     = local.name_prefix
  cidr                     = var.vpc_cidr
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_rag_subnet_cidrs = var.private_rag_subnet_cidrs
}
/*
module "ingress" {
  source                  = "../../modules/ingress"
  name                    = local.name_prefix
  vpc_id                  = module.vpc.vpc_id
  public_subnet_ids       = module.vpc.public_subnet_ids
  alb_security_group_id   = module.vpc.alb_sg_id       # from your vpc module outputs
  api_gateway_sg_id       = module.vpc.api_gw_sg_id    # if defined
  domain_name             = "${var.tenant_id}.api.${var.project}.com"
}
*/
module "monolith_asg" {
  source                  = "../../modules/monolith_asg"
  name                    = "${local.name_prefix}-web"
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_app_subnet_ids
  instance_type           = var.web_instance_type
  min_size                = var.web_min_size
  max_size                = var.web_max_size
  desired_capacity        = var.web_desired_capacity
  #assets_bucket           = module.data_services.assets_bucket_name # if used in userdata
  # Add missing variables required by the module
  sqs_queue_arn              = module.rag_pipeline.queue_arn
  secrets_manager_secret_arn = element(module.data_services.secrets_manager_secret_arns, 0)
}

module "agentic_asg" {
  source                            = "../../modules/agentic_asg"
  name                              = "${local.name_prefix}-agentic"
  vpc_id                            = module.vpc.vpc_id
  private_subnet_ids                = module.vpc.private_app_subnet_ids

  allowed_source_security_group_ids = [
    module.monolith_asg.security_group_id
  ]

  instance_type                     = var.agentic_instance_type
  min_size                          = var.agentic_min_size
  max_size                          = var.agentic_max_size
  desired_capacity                  = var.agentic_desired_capacity

  s3_bucket_name                    = module.data_services.bucket_name
  sqs_queue_arn                     = module.rag_pipeline.queue_arn
  sqs_queue_url                     = module.rag_pipeline.queue_url
  secrets_manager_secret_arn        = module.data_services.secrets_manager_secret_arns[0]
  region                            = var.region
}

module "data_services" {
  source              = "../../modules/data_services"
  name                = local.name_prefix
  tenant_id           = var.tenant_id
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_app_subnet_ids
  region              = var.region

  # example: pass initial secrets if you want auto-creation
  secrets = {
    "db_password" = "changeme123"
  }
}

module "rag_pipeline" {
  source                         = "../../modules/rag_pipeline"
  name                           = local.name_prefix
  tenant_id                      = var.tenant_id
  region                         = var.region
  private_subnet_ids             = module.vpc.private_rag_subnet_ids
  vpc_id               = module.vpc.vpc_id  
  chunk_lambda_s3_bucket         = var.chunk_lambda_s3_bucket
  chunk_lambda_s3_key            = var.chunk_lambda_s3_key
  embed_lambda_s3_bucket         = var.embed_lambda_s3_bucket
  embed_lambda_s3_key            = var.embed_lambda_s3_key
  index_lambda_s3_bucket         = var.index_lambda_s3_bucket
  index_lambda_s3_key            = var.index_lambda_s3_key
  secrets_manager_secret_arn     = element(module.data_services.secrets_manager_secret_arns, 0)
}


module "iam" {
  source                  = "../../modules/iam"
  # …any shared IAM roles or policies your other modules need…
}
/*
module "monitoring" {
  source                  = "../../modules/monitoring"
  name                    = local.name_prefix
  # …pass ARNs or names of your ASGs, ALB, Lambdas, etc., to hook up alarms…
}
*/
resource "aws_security_group_rule" "agentic_to_data_redis" {
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = module.agentic_asg.security_group_id
  security_group_id        = module.data_services.data_services_security_group_id
  description              = "Allow Agentic ASG to Redis"
}

resource "aws_security_group_rule" "agentic_to_data_qdrant" {
  type                     = "ingress"
  from_port                = 6333
  to_port                  = 6333
  protocol                 = "tcp"
  source_security_group_id = module.agentic_asg.security_group_id
  security_group_id        = module.data_services.data_services_security_group_id
  description              = "Allow Agentic ASG to Qdrant"
}