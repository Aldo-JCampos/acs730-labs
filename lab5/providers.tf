provider "aws" {
  region = var.aws_region

  # Deliberately fake: LocalStack checks that a credential was SENT, not
  # that it is valid. When false, these are null and the provider falls
  # back to the normal chain -- here, the LabRole profile.
  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null

  # Each of these turns off a call that only makes sense against real AWS.
  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack
  skip_region_validation      = var.use_localstack

  # LocalStack serves every bucket from one host, so the bucket name has
  # to travel in the path, not in the hostname.
  s3_use_path_style = var.use_localstack

  # An empty list means zero endpoints blocks, which means the real AWS
  # endpoints. This is how one provider block serves two targets.
  dynamic "endpoints" {
    for_each = var.use_localstack ? [1] : []
    content {
      ec2 = var.localstack_endpoint
      s3  = var.localstack_endpoint
      sts = var.localstack_endpoint
      iam = var.localstack_endpoint
    }
  }

  default_tags {
    tags = {
      Course = "ACS730"
      Lab    = "lab5"
      Owner  = var.owner
    }
  }
}
