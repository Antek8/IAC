# modules/vpc/variables.tf

variable "name" {
  type = string
}

variable "cidr" {
  type = string
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_app_subnet_cidrs" {
  type = list(string)
}

variable "private_rag_subnet_cidrs" {
  type = list(string)
}

# ADDED: This variable was used in main.tf for endpoints but was not declared.
variable "region" {
  description = "The AWS region to create VPC endpoints in."
  type        = string
}
