# ─────────────────────────────────────────────────────────────────────────────
# Per-account baseline.
#
# Applied to EVERY account so a new one is consistent and safe before anything is
# deployed into it. Part of a multi-account landing-zone baseline.
#
# WHAT IS DELIBERATELY NOT HERE
#
# AWS Config. It bills per configuration item recorded plus per rule evaluation, and it
# belongs with a delegated security admin account that owns Config history org-wide. An org-level recorder configured there beats one per account
# configured here, and turning it on in every account first would be work E3 then has
# to undo.
#
# Cross-account log, backup and monitoring wiring. The spec lists it in the baseline,
# but the target accounts do not exist yet, so there are no ARNs to point at. Adding the variables now would ship an interface guessed rather than designed.
# It lands in a later module version once those accounts are real.
#
# Provider default_tags. A module cannot set them -- they are provider configuration, so
# the CONSUMER must declare them. See the README; this module deliberately does not
# pretend to cover it.
# ─────────────────────────────────────────────────────────────────────────────

# ─── EBS default encryption, per region ──────────────────────────────────────
#
# The account-wide switch, not a per-resource one, and that distinction is the whole
# point. Setting encrypted = true on every launch template we own still leaves anything
# AWS provisions on our behalf unencrypted -- Elastic Beanstalk creates its own volumes
# and takes no block-device configuration from our Terraform, which is how
# one account ended up with unencrypted Elastic Beanstalk volumes found by a compliance
# scan.
#
# From here on every new volume in this account and region is encrypted regardless of
# who creates it: EB, an ASG, a console click, another Terraform repo.
#
# ⚠️ ONLY AFFECTS NEW VOLUMES. Existing volumes cannot be encrypted in place -- there is
# no API for it. They stay unencrypted until their instances are replaced. Do not read
# this resource as remediation of anything already running. A volume whose instance
# cannot be replaced stays unencrypted indefinitely, and that case does occur.
#
# DELIBERATELY NO CUSTOMER-MANAGED KEY. A CMK adds a well-known failure mode: Auto
# Scaling launches volumes through a service-linked role, and unless that role holds
# kms:CreateGrant on the key, launches start failing -- surfacing as an ASG that cannot
# scale, not as a Terraform error. The AWS-managed aws/ebs key satisfies the control.
resource "aws_ebs_encryption_by_default" "this" {
  for_each = toset(var.ebs_encryption_regions)

  region  = each.key
  enabled = true
}

# ─── S3 account-wide public access block ─────────────────────────────────────
#
# Account settings OVERRIDE per-bucket ones, which makes this the strongest S3 control
# available and also the easiest one to break a working bucket with. See the variable's
# documentation for the public-bucket case before enabling it on an account that
# serves public objects.
resource "aws_s3_account_public_access_block" "this" {
  count = var.manage_s3_account_public_access_block ? 1 : 0

  block_public_acls       = var.s3_block_public_acls
  block_public_policy     = var.s3_block_public_policy
  ignore_public_acls      = var.s3_ignore_public_acls
  restrict_public_buckets = var.s3_restrict_public_buckets
}

# ─── IAM account password policy ─────────────────────────────────────────────
#
# A compliance control more than a practical one -- access is through Identity Center,
# so a well-run account has no IAM users with console passwords for this to govern.
# Scanners check it, it costs nothing, so it is on by default.
#
# No password_reuse_prevention: it is only meaningful alongside rotation, and rotation
# for a population of zero IAM users is theatre. Left out rather than set to a number
# that implies more than it delivers.
resource "aws_iam_account_password_policy" "this" {
  count = var.manage_iam_password_policy ? 1 : 0

  minimum_password_length        = var.iam_minimum_password_length
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = var.iam_password_max_age_days
}
