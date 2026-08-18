# Validation harness for modules/s3-bucket. Not applied against any account —
# `terraform validate` only. Exercises every profile, the policy merge, and each
# dynamic block, so a shape error surfaces here rather than in a consumer repo.
#
# Placeholder names only: this repo is public and must contain no real account
# ids, bucket names, or ARNs.

terraform {
  required_version = ">= 1.2"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

# A log target bucket: the one case that must opt out of logging.
module "log_target" {
  source = "../../modules/s3-bucket"

  name           = "example-log-target"
  purpose        = "logs"
  data_class     = "internal"
  enable_logging = false
}

# Exercises: prefix filter, transition list, expiration,
# noncurrent_version_expiration, abort_incomplete_multipart_upload, extra policy
# merge, and the TLS>=1.2 floor from the confidential profile.
data "aws_iam_policy_document" "extra" {
  statement {
    sid    = "AllowExampleRoleRead"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::111111111111:role/example"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${module.confidential.arn}/*"]
  }
}

module "confidential" {
  source = "../../modules/s3-bucket"

  name              = "example-confidential"
  purpose           = "archive"
  data_class        = "confidential"
  log_target_bucket = module.log_target.id

  tags = {
    Category = "Data"
  }

  extra_policy_json = [data.aws_iam_policy_document.extra.json]

  lifecycle_rules = [
    {
      id         = "all objects"
      expiration = { days = 365 }
    },
    {
      id     = "prefixed with transitions"
      filter = { prefix = "exports/" }
      transition = [
        { days = 30, storage_class = "STANDARD_IA" },
        { days = 90, storage_class = "GLACIER" },
      ]
      expiration                        = { days = 400 }
      noncurrent_version_expiration     = { noncurrent_days = 30 }
      abort_incomplete_multipart_upload = { days_after_initiation = 7 }
    },
  ]
}

# Exercises: required CMK + deny-unencrypted-upload, and CORS.
module "phi" {
  source = "../../modules/s3-bucket"

  name              = "example-phi"
  purpose           = "documents"
  data_class        = "phi"
  log_target_bucket = module.log_target.id
  kms_key_arn       = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000"

  cors_rules = [
    {
      allowed_methods = ["GET", "PUT"]
      allowed_origins = ["https://example.invalid"]
      allowed_headers = ["*"]
      max_age_seconds = 3000
    },
  ]
}

module "cdn_origin" {
  source = "../../modules/s3-bucket"

  name              = "example-cdn-origin"
  purpose           = "website"
  data_class        = "cdn_origin"
  log_target_bucket = module.log_target.id
}

# The audited exception: all four public-access-block flags off.
module "public_website" {
  source = "../../modules/s3-bucket"

  name               = "example-public-website"
  purpose            = "www"
  data_class         = "public_website"
  acknowledge_public = true
  log_target_bucket  = module.log_target.id
}
