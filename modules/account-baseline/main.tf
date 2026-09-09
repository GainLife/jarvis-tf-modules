# ─────────────────────────────────────────────────────────────────────────────
# Per-account baseline.
#
# Applied to every account so a new one is consistent and safe before anything is
# deployed into it.
#
# WHAT IS DELIBERATELY NOT HERE
#
# AWS Config. It bills per configuration item recorded plus per rule evaluation, and it
# belongs with a delegated security-admin account that owns Config history org-wide. An
# org-level recorder configured there beats one per account configured here.
#
# Cross-account log, backup and monitoring wiring. The target accounts do not exist yet,
# so there are no ARNs to point at, and adding variables now would fix an interface
# before it is designed. It lands in a later module version.
#
# Provider default_tags. A module CANNOT set them -- they are provider configuration, so
# the CONSUMER must declare them. See the README; this module deliberately does not
# pretend to cover it.
# ─────────────────────────────────────────────────────────────────────────────

# ─── EBS default encryption, per region ──────────────────────────────────────
#
# The account-wide switch, not a per-resource one, and that distinction is the point.
# Setting encrypted = true on every launch template you own still leaves anything AWS
# provisions on your behalf unencrypted -- Elastic Beanstalk creates its own volumes and
# takes no block-device configuration from Terraform, which is how one account ended up
# with unencrypted EB volumes found by a compliance scan.
#
# From here on every new volume in this account and region is encrypted regardless of
# who creates it: an ASG, a managed service, a console click, another Terraform repo.
#
# ⚠️ ONLY AFFECTS NEW VOLUMES. Existing volumes cannot be encrypted in place -- there is
# no API for it. They stay unencrypted until their instances are replaced. Do not read
# this resource as remediation of anything already running: a volume whose instance
# cannot be replaced stays unencrypted indefinitely, and that case does occur.
#
# ON THE ENCRYPTION KEY. This enables default encryption but does NOT manage which key
# is used -- aws_ebs_default_kms_key is deliberately not set here, so whatever the
# account already has stays in force: the AWS-managed aws/ebs key if nothing was
# configured, or an existing customer-managed key if one was.
#
# That matters, because a CMK carries a well-known failure mode: Auto Scaling launches
# volumes through a service-linked role, and unless that role holds kms:CreateGrant on
# the key, launches start failing -- surfacing as an ASG that cannot scale rather than
# as a Terraform error. This module does not introduce that risk, and it does not
# protect you from it either. If an account already has a CMK default, verify the grant.
resource "aws_ebs_encryption_by_default" "this" {
  for_each = toset(var.ebs_encryption_regions)

  region  = each.key
  enabled = true
}

# ─── S3 account-wide public access block ─────────────────────────────────────
#
# Off by default. Account settings OVERRIDE per-bucket ones, which makes this the
# strongest S3 control available and also the easiest way to break a working bucket:
# some accounts legitimately serve public objects. See the variable's documentation.
#
# prevent_destroy is load-bearing here rather than decorative. Without it, flipping
# manage_s3_account_public_access_block from true to false takes count to 0, Terraform
# destroys the block, and the account silently goes back to allowing what it was
# preventing -- a security regression that reads as a routine resource removal in a
# plan. With it, that plan fails and someone has to decide on purpose.
#
# To genuinely stop managing the setting without changing it: terraform state rm.
resource "aws_s3_account_public_access_block" "this" {
  count = var.manage_s3_account_public_access_block ? 1 : 0

  block_public_acls       = var.s3_block_public_acls
  block_public_policy     = var.s3_block_public_policy
  ignore_public_acls      = var.s3_ignore_public_acls
  restrict_public_buckets = var.s3_restrict_public_buckets

  lifecycle {
    prevent_destroy = true
  }
}

# ─── IAM account password policy ─────────────────────────────────────────────
#
# A compliance control more than a practical one -- where access is through an identity
# provider, a well-run account has no IAM users with console passwords for this to
# govern. Scanners check it, it costs nothing, so it is on by default.
#
# No password_reuse_prevention: it is only meaningful alongside rotation, and rotation
# for a population of zero IAM users is theatre. Left out rather than set to a number
# that implies more than it delivers.
#
# prevent_destroy for the same reason as the S3 block: destroying this reverts the
# account to AWS defaults, which are weaker than what it sets. That is a posture change,
# not an unmanage, and it should not be reachable by flipping a boolean.
resource "aws_iam_account_password_policy" "this" {
  count = var.manage_iam_password_policy ? 1 : 0

  minimum_password_length        = var.iam_minimum_password_length
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = var.iam_password_max_age_days

  lifecycle {
    prevent_destroy = true
  }
}
