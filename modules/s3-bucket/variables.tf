variable "name" {
  description = <<-EOT
    Full bucket name, used verbatim.

    `bucket` is the ONLY ForceNew field on aws_s3_bucket. If this differs by even
    one character from an existing bucket's name during a migration, Terraform
    plans a destroy + recreate of live data. Always read a migration plan for
    "must be replaced" before applying.
  EOT
  type        = string
}

variable "purpose" {
  description = <<-EOT
    Short slug identifying what the bucket is for. Used for the Name tag and as
    the server-access-log prefix. Example: "archive".
  EOT
  type        = string

  # AWS rejects tag values outside [letters digits whitespace _ . : / = + - @]
  # with InvalidTag. That failure happens at APPLY time, mid-run, after earlier
  # resources have already changed — `terraform plan` does not catch it. This
  # validation moves it to plan time. See the Gotchas section of the consumer
  # repo's CLAUDE.md; PR #392 died this way on an aws_s3_bucket Purpose tag.
  validation {
    condition     = can(regex("^[[:alnum:] _.:/=+@-]+$", var.purpose))
    error_message = "purpose becomes a tag value, so it may only contain letters, digits, whitespace, and _ . : / = + - @ — no parentheses or commas (AWS rejects them with InvalidTag at apply time)."
  }
}

variable "data_class" {
  description = <<-EOT
    Security profile. One input selects a whole posture rather than exposing a
    boolean per control.

      cdn_origin     - reached only via a CloudFront service principal scoped by
                       AWS:SourceArn. Public access fully blocked. This is NOT
                       "a public bucket".
      internal       - service-to-service, accessed by IAM principals only.
      confidential   - as internal, plus a TLS>=1.2 floor.
      phi            - as confidential, plus a required CMK and a deny on
                       unencrypted uploads.
      public_website - the audited exception. Turns OFF all four public-access
                       block flags so a Principal:"*" read policy can apply.
                       Requires acknowledge_public = true.
  EOT
  type        = string

  validation {
    condition = contains(
      ["cdn_origin", "internal", "confidential", "phi", "public_website"],
      var.data_class
    )
    error_message = "data_class must be one of: cdn_origin, internal, confidential, phi, public_website."
  }
}

variable "acknowledge_public" {
  description = <<-EOT
    Required to be true when data_class = "public_website", which disables all
    public-access-block protection. Exists so a bucket cannot become
    internet-readable through a one-word edit.
  EOT
  type        = bool
  default     = false
}

variable "object_ownership" {
  description = <<-EOT
    Object ownership setting. Defaults to BucketOwnerEnforced, which disables ACLs and
    is the intended end state for every bucket.

    "BucketOwnerPreferred" is a MIGRATION-ONLY escape hatch. AWS rejects
    PutBucketOwnershipControls with InvalidBucketAclWithObjectOwnership if the bucket
    still carries ACL grants beyond the owner's own — and `terraform plan` shows that
    change as a clean update, so the failure lands mid-apply.

    Deleting an aws_s3_bucket_acl resource does NOT clear those grants: that
    resource's delete is a state-only no-op in the AWS provider. The grants must be
    overwritten with a private ACL first.

    So a bucket with custom ACL grants migrates in two applies:
      1. object_ownership = "BucketOwnerPreferred", plus an aws_s3_bucket_acl with
         acl = "private" in the caller, to overwrite the grants.
      2. drop both — ownership returns to the BucketOwnerEnforced default.

    A bucket left on BucketOwnerPreferred is NOT finished migrating.
  EOT
  type        = string
  default     = "BucketOwnerEnforced"

  validation {
    condition     = contains(["BucketOwnerEnforced", "BucketOwnerPreferred"], var.object_ownership)
    error_message = "object_ownership must be BucketOwnerEnforced (the default) or BucketOwnerPreferred (migration only). ObjectWriter is deliberately not offered."
  }
}

variable "enable_logging" {
  description = <<-EOT
    Set false only for a log target bucket itself, which cannot log to itself.
  EOT
  type        = bool
  default     = true
}

variable "log_target_bucket" {
  description = "Bucket id receiving server access logs. Required unless enable_logging = false."
  type        = string
  default     = null
}

variable "use_cmk" {
  description = <<-EOT
    Opt a non-phi bucket onto a customer-managed key. `phi` always uses one
    regardless of this value.

    Switching an existing bucket from AES256 to a CMK is not retroactive —
    existing objects keep the key they were written with — and every IAM
    principal that reads the bucket needs kms:Decrypt added FIRST, or reads
    break at runtime rather than at plan time.
  EOT
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "CMK ARN. Required when data_class = \"phi\" or use_cmk = true."
  type        = string
  default     = null
}

variable "lifecycle_rules" {
  description = <<-EOT
    Lifecycle rules. An empty list means the lifecycle configuration resource is
    not created at all, rather than created empty.

    Supported per rule (matching what the consumer repos actually use):
      id                                - required
      status                            - defaults to "Enabled"
      filter                            - { prefix = "..." }; omit for all objects
      expiration                        - { days = N }
      noncurrent_version_expiration     - { noncurrent_days = N }
      abort_incomplete_multipart_upload - { days_after_initiation = N }
      transition                        - list of { days = N, storage_class = "..." }

    Example:
      [
        {
          id         = "expire old exports"
          filter     = { prefix = "exports/" }
          transition = [{ days = 30, storage_class = "STANDARD_IA" }]
          expiration = { days = 365 }
        },
      ]
  EOT
  type        = any
  default     = []
}

variable "extra_policy_json" {
  description = <<-EOT
    Rendered IAM policy document JSON strings, merged into this module's baseline
    bucket policy via source_policy_documents. Callers keep writing their own
    `data "aws_iam_policy_document"` and pass `.json`.

    Nothing passed here can drop the baseline statements.

    Do NOT pass a SecureTransport deny — the module always emits one, scoped to
    both the bucket and the object ARN. When migrating a bucket, DELETE its
    hand-written TLS statement rather than passing it through.
  EOT
  type        = list(string)
  default     = []
}

variable "cors_rules" {
  description = <<-EOT
    CORS rules. Empty list means no CORS configuration resource is created.

    Supported per rule: allowed_methods, allowed_origins (both required),
    allowed_headers, expose_headers, max_age_seconds.
  EOT
  type        = any
  default     = []
}

variable "force_destroy" {
  description = <<-EOT
    Defaults false, matching every bucket in both consumer repos.

    A non-empty bucket with force_destroy = false fails to destroy and stalls the
    WHOLE apply with BucketNotEmpty. Set true only for genuinely ephemeral
    buckets whose contents are disposable.
  EOT
  type        = bool
  default     = false
}

variable "tags" {
  description = <<-EOT
    Merged over the module's standard tags, and wins on key collisions.

    When migrating an existing bucket, pass its current tags here (e.g.
    Category) or the first apply will show them being removed.

    Keys and values are validated against AWS's tag charset, because InvalidTag
    is an apply-time failure that no plan reveals.
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for v in values(var.tags) : can(regex("^[[:alnum:] _.:/=+@-]*$", v))
    ])
    error_message = "Tag VALUES may only contain letters, digits, whitespace, and _ . : / = + - @ — no parentheses or commas. AWS rejects the rest with InvalidTag at apply time, mid-run, after earlier resources have already changed."
  }

  validation {
    condition = alltrue([
      for k in keys(var.tags) : can(regex("^[[:alnum:] _.:/=+@-]+$", k))
    ])
    error_message = "Tag KEYS may only contain letters, digits, whitespace, and _ . : / = + - @ — no parentheses or commas."
  }
}
