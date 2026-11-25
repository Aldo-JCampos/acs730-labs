terraform {
  backend "s3" {
    bucket       = "acs730-tfstate-615313524491"
    key          = "assignment1/staging/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
