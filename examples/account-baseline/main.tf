# Validate-only example: exercises the module with defaults so `terraform validate`
# catches interface breakage. Not applied anywhere.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  # The module cannot set default_tags -- they are provider configuration. Declared here
  # to show consumers what they are responsible for.
  default_tags {
    tags = {
      App         = "Example"
      Environment = "example"
    }
  }
}

module "baseline_defaults" {
  source = "../../modules/account-baseline"
}

# The shape for an account that serves a public website bucket: the account-wide block
# must not override that bucket's own block_public_policy = false.
module "baseline_public_bucket_account" {
  source = "../../modules/account-baseline"

  s3_block_public_policy = false
}
