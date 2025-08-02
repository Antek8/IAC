
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

variable "region" {
  description = "The AWS region to create VPC endpoints in."
  type        = string
}

variable "fck_nat_ssh_ipv4_cidr_blocks" {
  description = "A list of IPv4 CIDR blocks to allow SSH access to the fck-nat instance."
  type        = list(string)
  default     = []
}