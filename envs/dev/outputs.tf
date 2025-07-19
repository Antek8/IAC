# envs/dev/outputs.tf

# The 'ingress' module is commented out in main.tf, so these outputs are invalid.
# output "alb_dns"          { value = module.ingress.alb_dns_name }
# output "api_gateway_url"  { value = module.ingress.api_gateway_invoke_url }

output "web_asg_name" {
  value = module.monolith_asg.asg_name
}

output "rag_queue_url" {
   value = module.rag_pipeline.high_priority_queue_url
}
