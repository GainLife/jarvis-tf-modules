variable "ebs_encryption_regions" {
  description = <<-DESC
    Regions to enable EBS default encryption in. Defaults to every region enabled for
    the organization today.

    STATIC BY DESIGN, not `data "aws_regions"`. Opting into a new region should be a
    conscious edit here, not silent resource churn the next time someone enables one --
    the same reasoning used for the org-wide GuardDuty region list.
  DESC
  type        = list(string)
  default = [
    "ap-northeast-1", "ap-northeast-2", "ap-northeast-3", "ap-south-1",
    "ap-southeast-1", "ap-southeast-2", "ca-central-1", "eu-central-1",
    "eu-north-1", "eu-west-1", "eu-west-2", "eu-west-3", "sa-east-1",
    "us-east-1", "us-east-2", "us-west-1", "us-west-2",
  ]
}

variable "manage_s3_account_public_access_block" {
  description = <<-DESC
    Whether to manage the ACCOUNT-WIDE S3 public access block.

    ⚠️ READ THIS BEFORE SETTING IT TRUE ON AN ACCOUNT THAT SERVES A PUBLIC BUCKET.

    Account-level settings OVERRIDE per-bucket ones. A bucket that deliberately allows a
    public policy stops working the moment the account blocks it, and nothing about the
    bucket's own configuration will explain why.

    There is a live example: jarvis-global-infrastructure/tf/www.tf sets
    block_public_policy = false on purpose, and §3.4 of the multi-account spec moves
    www.tf into the Shared Apps account. That account therefore needs
    s3_block_public_policy = false, or the www bucket breaks.

    Default true because blocking is right for every account that does not serve public
    objects, which is most of them.
  DESC
  type        = bool
  default     = true
}

variable "s3_block_public_acls" {
  description = "Account-wide: reject PutBucketAcl / PutObjectAcl calls that grant public access."
  type        = bool
  default     = true
}

variable "s3_block_public_policy" {
  description = "Account-wide: reject bucket policies that grant public access. Set false for an account that serves a public bucket - see manage_s3_account_public_access_block."
  type        = bool
  default     = true
}

variable "s3_ignore_public_acls" {
  description = "Account-wide: ignore any public ACL already present, rather than rejecting new ones."
  type        = bool
  default     = true
}

variable "s3_restrict_public_buckets" {
  description = "Account-wide: restrict access to buckets with public policies to the bucket owner and AWS services only."
  type        = bool
  default     = true
}

variable "manage_iam_password_policy" {
  description = <<-DESC
    Whether to set the account IAM password policy.

    Mostly a compliance control rather than a practical one: access is through IAM
    Identity Center, so a well-run account has no IAM users with console passwords for
    this to apply to. It is still checked by scanners, and it costs nothing, so it is on
    by default -- but do not read its presence as evidence that IAM users exist.
  DESC
  type        = bool
  default     = true
}

variable "iam_minimum_password_length" {
  description = "Minimum IAM console password length. 14 is the CIS Benchmark value."
  type        = number
  default     = 14
}

variable "iam_password_max_age_days" {
  description = "Maximum IAM console password age in days. 0 disables expiry."
  type        = number
  default     = 90
}
