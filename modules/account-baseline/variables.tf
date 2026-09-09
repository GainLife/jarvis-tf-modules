variable "ebs_encryption_regions" {
  description = <<-DESC
    Regions to enable EBS default encryption in. Defaults to the commercial regions
    enabled for this organization.

    STATIC BY DESIGN, not `data "aws_regions"`. Opting into a new region should be a
    conscious edit here, not silent resource churn the next time someone enables one.

    Duplicates are harmless -- the resource is keyed on a set.
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

    DEFAULTS TO FALSE, deliberately, because some accounts serve public S3 objects.

    Account-level settings OVERRIDE per-bucket ones. An account-wide block therefore
    breaks a bucket that deliberately allows a public policy, and nothing about that
    bucket's own configuration will explain why. Defaulting this to true would mean
    applying the baseline to such an account silently breaks it, which is the wrong
    behaviour for a module meant to be safe to adopt.

    RECOMMENDED TRUE for any account that does not serve public objects, which is most
    of them. Per-bucket blocks are the primary control; this is defence in depth for
    the case where someone creates a bucket without one.

    ⚠️ TURNING THIS OFF AGAIN IS NOT A NO-OP. Once applied as true, flipping it to false
    means Terraform DESTROYS the account-level block, re-allowing what it was
    preventing. prevent_destroy is set on the resource so that fails the plan rather
    than happening quietly -- see main.tf. To stop managing the setting without changing
    it, remove the resource from state instead.
  DESC
  type        = bool
  default     = false
}

variable "s3_block_public_acls" {
  description = "Account-wide: reject PutBucketAcl / PutObjectAcl calls that grant public access. Applies only when manage_s3_account_public_access_block is true."
  type        = bool
  default     = true
}

variable "s3_block_public_policy" {
  description = "Account-wide: reject bucket policies that grant public access. Set false for an account that serves a public bucket, so the account setting does not override that bucket's own configuration."
  type        = bool
  default     = true
}

variable "s3_ignore_public_acls" {
  description = "Account-wide: ignore any public ACL already present, rather than only rejecting new ones."
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

    Mostly a compliance control rather than a practical one: where access is through an
    identity provider, a well-run account has no IAM users with console passwords for
    this to apply to. Scanners still check it and it costs nothing, so it is on by
    default -- but do not read its presence as evidence that IAM users exist.

    ⚠️ Same caveat as the S3 block: flipping this true -> false DESTROYS the policy,
    reverting the account to AWS defaults, which are weaker than what this sets. That is
    a posture change, not an unmanage. prevent_destroy makes it fail the plan instead.
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
