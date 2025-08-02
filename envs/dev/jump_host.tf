# envs/dev/jump_host.tf

resource "aws_security_group_rule" "allow_ssh_to_jump_host" {
  for_each = toset(var.my_ips_for_ssh)

  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [each.key] # Corrected: Use the value directly
  security_group_id = module.vpc.fck_nat_security_group_id
  description       = "Allow SSH from ${each.key} to the jump host"
}


# Rule 2: Allow SSH from the jump host to the Monolith ASG instances.
resource "aws_security_group_rule" "allow_jump_to_monolith" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = module.vpc.fck_nat_security_group_id
  security_group_id        = module.monolith_asg.security_group_id
  description              = "Allow SSH from jump host to Monolith instances"
}

# Rule 3: Allow SSH from the jump host to the Agentic ASG instances.
resource "aws_security_group_rule" "allow_jump_to_agentic" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = module.vpc.fck_nat_security_group_id
  security_group_id        = module.agentic_asg.security_group_id
  description              = "Allow SSH from jump host to Agentic instances"
}

resource "aws_security_group_rule" "allow_jump_to_qdrant" {
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = module.vpc.fck_nat_security_group_id
  security_group_id        = module.data_services.data_services_security_group_id
  description              = "Allow SSH from jump host to Qdrant instance"
}
