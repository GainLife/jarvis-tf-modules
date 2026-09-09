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

# An account with no public objects: turn the account-wide block on.
module "baseline_block_public" {
  source = "../../modules/account-baseline"

  manage_s3_account_public_access_block = true
}

# An account that serves one public bucket: keep the block on and relax the single flag,
# rather than abandoning all four protections.
module "baseline_public_bucket_account" {
  source = "../../modules/account-baseline"

  manage_s3_account_public_access_block = true
  s3_block_public_policy                = false
}
