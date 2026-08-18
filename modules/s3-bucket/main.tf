# ─────────────────────────────────────────────────────────────────────────────
# Standardized S3 bucket.
#
# One `data_class` input selects a whole security profile. This is deliberate:
# exposing a boolean per control just relocates the guessing from copy-paste
# into module arguments, which is the failure this module exists to fix.
#
# The baseline below cannot be switched off by a caller. Callers extend the
# bucket policy through var.extra_policy_json, which merges via
# source_policy_documents (see policy.tf) rather than replacing anything.
#
# NOT handled here, on purpose:
#   - aws_s3_bucket_notification  - shape varies too much (lambda/sqs/sns/
#                                   eventbridge) to model without a leaky `any`.
#   - aws_s3_bucket_replication_configuration
#   - aws_s3_bucket_acl           - ACLs are disabled (BucketOwnerEnforced).
# Declare the first two in the caller against the module's `id` output.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  profiles = {
    # Reached only via a CloudFront service principal scoped by AWS:SourceArn.
    cdn_origin = {
      block_public         = true
      require_cmk          = false
      deny_old_tls         = false
      deny_unencrypted_put = false
    }

    internal = {
      block_public         = true
      require_cmk          = false
      deny_old_tls         = false
      deny_unencrypted_put = false
    }

    confidential = {
      block_public         = true
      require_cmk          = false
      deny_old_tls         = true
      deny_unencrypted_put = false
    }

    phi = {
      block_public         = true
      require_cmk          = true
      deny_old_tls         = true
      deny_unencrypted_put = true
    }

    # The audited exception. One consumer bucket serves a website directly and
    # grants s3:GetObject to Principal "*"; forcing the public-access-block
    # flags on would make that policy unappliable and take the site down.
    # Gated behind acknowledge_public. Moving such a bucket behind CloudFront
    # + OAC and deleting this profile is the right end state.
    public_website = {
      block_public         = false
      require_cmk          = false
      deny_old_tls         = false
      deny_unencrypted_put = false
    }
  }

  profile = local.profiles[var.data_class]

  use_cmk       = local.profile.require_cmk || var.use_cmk
  sse_algorithm = local.use_cmk ? "aws:kms" : "AES256"

  tags = merge(
    {
      Name      = var.purpose
      DataClass = var.data_class
      ManagedBy = "jarvis-tf-modules/s3-bucket"
    },
    var.tags,
  )
}

resource "aws_s3_bucket" "this" {
  bucket        = var.name
  force_destroy = var.force_destroy
  tags          = local.tags

  # NOTE: deliberately NO `ignore_changes = [tags]`. Most pre-existing buckets in
  # the consumer repos carry it, which is precisely why tag drift was never
  # reconcilable there.

  lifecycle {
    precondition {
      condition     = !local.use_cmk || var.kms_key_arn != null
      error_message = "kms_key_arn is required when data_class = \"phi\" or use_cmk = true."
    }

    precondition {
      condition     = var.data_class != "public_website" || var.acknowledge_public
      error_message = "data_class = \"public_website\" disables all public-access-block protection; set acknowledge_public = true to confirm this is intended."
    }

    precondition {
      condition     = !var.enable_logging || var.log_target_bucket != null
      error_message = "log_target_bucket is required unless enable_logging = false."
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = local.profile.block_public
  block_public_policy     = local.profile.block_public
  ignore_public_acls      = local.profile.block_public
  restrict_public_buckets = local.profile.block_public
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status     = "Enabled"
    mfa_delete = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.sse_algorithm
      kms_master_key_id = local.use_cmk ? var.kms_key_arn : null
    }

    # S3 Bucket Keys apply to SSE-KMS only — they collapse per-object KMS calls
    # into per-bucket ones and cut KMS request cost by ~2 orders of magnitude.
    # Left unset for AES256, where there are no KMS requests to collapse and the
    # field is inert; setting it there risks a perpetual diff for no benefit.
    bucket_key_enabled = local.use_cmk ? true : null
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    # Defaults to BucketOwnerEnforced — the modern default, which disables ACLs.
    #
    # Two failure modes neither of which a plan reveals:
    #   1. AWS rejects this with InvalidBucketAclWithObjectOwnership if the bucket
    #      still has ACL grants beyond the owner's. Destroying an aws_s3_bucket_acl
    #      does NOT clear them (its delete is a state-only no-op) — they must be
    #      overwritten with a private ACL first. See var.object_ownership for the
    #      two-apply migration.
    #   2. Once enforced, any writer sending x-amz-acl fails at RUNTIME with
    #      AccessControlListNotSupported.
    object_ownership = var.object_ownership
  }
}

resource "aws_s3_bucket_logging" "this" {
  count = var.enable_logging ? 1 : 0

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.log_target_bucket
  target_prefix = "${var.purpose}/"
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = length(var.lifecycle_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  # Versioning is always enabled here, and noncurrent_version_expiration rules
  # are meaningless before it exists.
  depends_on = [aws_s3_bucket_versioning.this]

  dynamic "rule" {
    for_each = var.lifecycle_rules

    content {
      id     = rule.value.id
      status = try(rule.value.status, "Enabled")

      # An empty filter {} targets every object, which is what a rule with no
      # declared filter means. The provider requires filter or prefix.
      filter {
        prefix = try(rule.value.filter.prefix, null)
      }

      dynamic "expiration" {
        for_each = try(rule.value.expiration, null) == null ? [] : [rule.value.expiration]
        content {
          days = expiration.value.days
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = try(rule.value.noncurrent_version_expiration, null) == null ? [] : [rule.value.noncurrent_version_expiration]
        content {
          noncurrent_days = noncurrent_version_expiration.value.noncurrent_days
        }
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = try(rule.value.abort_incomplete_multipart_upload, null) == null ? [] : [rule.value.abort_incomplete_multipart_upload]
        content {
          days_after_initiation = abort_incomplete_multipart_upload.value.days_after_initiation
        }
      }

      dynamic "transition" {
        for_each = try(rule.value.transition, [])
        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules

    content {
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      allowed_headers = try(cors_rule.value.allowed_headers, null)
      expose_headers  = try(cors_rule.value.expose_headers, null)
      max_age_seconds = try(cors_rule.value.max_age_seconds, null)
    }
  }
}
