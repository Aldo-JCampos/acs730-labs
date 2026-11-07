variable "aws_region" {
  description = "Region to build in. LocalStack ignores it, real AWS does not."
  type        = string
  default     = "us-east-1"
}
variable "use_localstack" {
  description = "When true, point every AWS endpoint at the LocalStack container."
  type        = bool
  default     = false
}
variable "localstack_endpoint" {
  description = "Where LocalStack listens. Read only when use_localstack is true."
  type        = string
  default     = "http://localhost:4566"
}
variable "project" {
  description = "Name prefix for every resource."
  type        = string
  default     = "acs730-lab5"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,23}$", var.project))
    error_message = "project: 3-24 lowercase letters, digits, hyphens, starting with a letter."
  }
}
variable "owner" {
  description = "Your Seneca username. Tagged onto everything. No default on purpose."
  type        = string
}
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.42.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR, for example 10.42.0.0/16."
  }
}
variable "public_subnets" {
  description = "Public subnets to create, keyed by a short stable name."
  type = map(object({
    cidr_block = string
    az_index   = number
  }))
  default = {
    a = { cidr_block = "10.42.1.0/24", az_index = 0 }
    b = { cidr_block = "10.42.2.0/24", az_index = 1 }
  }
}
variable "ingress_rules" {
  description = "Ingress rules for the web security group, rendered by a dynamic block."
  type = list(object({
    description = string
    port        = number
    cidr_blocks = list(string)
  }))
  default = [
    { description = "HTTP from anywhere", port = 80, cidr_blocks = ["0.0.0.0/0"] },
  ]
}
variable "instance_type" {
  description = "Instance type for the web server."
  type        = string
  default     = "t3.micro"
  validation {
    condition     = contains(["t3.micro", "t3.small"], var.instance_type)
    error_message = "Stay small: t3.micro or t3.small. The term budget is $50 in total."
  }
}
variable "localstack_ami_id" {
  description = "Placeholder AMI, used only against LocalStack, which has no AMI catalogue."
  type        = string
  default     = "ami-0c02fb55956c7d316"
}
variable "create_artifact_bucket" {
  description = "Create the optional artifact bucket. Gated with count, not for_each."
  type        = bool
  default     = false
}
