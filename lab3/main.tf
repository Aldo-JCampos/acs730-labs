terraform {
  required_version = "~> 1.10"
 
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
 
  backend "s3" {
    bucket       = "acs730-tfstate-615313524491"
    key          = "lab3/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
 
provider "aws" {
  region = "us-east-1"
}
 
variable "greeting" {
  type    = string
  default = "hello from Github Actions"
}
 
resource "aws_ssm_parameter" "lab3" {
  name  = "/acs730/lab3/greeting"
  type  = "String"
  value = var.greeting
}
