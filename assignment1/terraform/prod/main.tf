terraform {
  required_version = "~> 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Course = "ACS730"
    }
  }
}

module "web" {
  source         = "../modules/web"
  environment    = "prod"
  instance_count = 2
  instance_type  = "t3.micro"
}

output "instance_ids" {
  value = module.web.instance_ids
}

output "public_ips" {
  value = module.web.public_ips
}

output "alarm_names" {
  value = module.web.alarm_names
}

output "db_password_length" {
  value = module.web.db_password_length
}
