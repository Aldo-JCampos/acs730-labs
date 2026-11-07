terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # "5.60 or newer, not 6.0": bug fixes without a major version
      # renaming arguments underneath you.
      version = "~> 5.60"
    }
  }
}
