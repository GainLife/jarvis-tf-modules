# `s3-bucket`

A secure-by-default S3 bucket. One `data_class` input selects a whole security
profile, rather than exposing a boolean per control.

```hcl
module "archive" {
  source = "git::https://github.com/GainLife/jarvis-tf-modules.git//modules/s3-bucket?ref=s3-bucket/v1.2.0"

  name       = "example-prefix-${var.env}-archive"
  purpose    = "archive"
  data_class = "confidential"

  log_target_bucket = module.logs.id

  tags = {
    Category = "Data"
  }

  lifecycle_rules = [
    {
      id         = "expire"
      expiration = { days = var.is_prod ? 365 : 90 }
    },
  ]
}
```

## Profiles

| `data_class` | Encryption | Public access block | Extra policy denies |
|---|---|---|---|
| `cdn_origin` | AES256 | all on | TLS |
| `internal` | AES256 | all on | TLS |
| `confidential` | AES256, or CMK via `use_cmk` | all on | TLS, TLS < 1.2 |
| `phi` | CMK (required) + bucket key | all on | TLS, TLS < 1.2, unencrypted PUT |
| `public_website` | AES256 | **all off** | TLS |

`cdn_origin` is named for what it is: an origin reached only through a CloudFront
service principal scoped by `AWS:SourceArn`, with public access fully blocked. It is
not "a public bucket".

`public_website` is an audited exception for a bucket that genuinely serves the
internet with an `s3:GetObject` grant to `Principal: "*"`. It disables all four
public-access-block flags, so it requires `acknowledge_public = true`. Prefer
CloudFront + OAC and `cdn_origin` for anything new.

## The baseline you cannot switch off

Every profile emits:

- all four public-access-block flags (`true`, except `public_website`)
- versioning enabled
- a server-side encryption configuration — never absent
- `object_ownership = "BucketOwnerEnforced"` (ACLs disabled)
- server access logging, unless `enable_logging = false`
- standard tags, with **no** `ignore_changes = [tags]`
- a `DenyInsecureTransport` policy statement covering **both** the bucket and
  object ARN

That last one is the defect this module was built to eliminate. A statement scoped
only to `"${arn}/*"` covers objects but leaves `ListBucket`, `GetBucketPolicy`, and
`GetBucketLocation` reachable over plaintext HTTP.

## Tag charset is validated at plan time

AWS rejects tag keys and values containing anything outside
`letters digits whitespace _ . : / = + - @` — notably **no parentheses and no
commas** — with `InvalidTag`. That failure happens at *apply* time, mid-run, after
earlier resources have already changed; `terraform plan` does not catch it.

`purpose` and every key and value in `tags` are validated against that charset, so
the failure surfaces at `terraform validate` instead. A consumer PR was lost to this
exact problem on an `aws_s3_bucket` `Purpose` tag before the check existed.

## Extending the bucket policy

Pass rendered policy JSON; the module merges it via `source_policy_documents`:

```hcl
data "aws_iam_policy_document" "extra" {
  statement {
    sid       = "AllowServiceRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${module.example.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [var.some_role_arn]
    }
  }
}

module "example" {
  # ...
  extra_policy_json = [data.aws_iam_policy_document.extra.json]
}
```

**Do not pass a `SecureTransport` deny.** The module always emits one, correctly
scoped. When migrating an existing bucket, delete its hand-written TLS statement
rather than passing it through.

If you do pass a statement whose `Sid` collides with a baseline one, the merge is
silent rather than an error: the statements are combined and the baseline's
resources survive (verified — the bucket ARN is still present). Don't rely on that;
it is a safety net, not a feature.

## Not handled here

Declare these in the caller, against the `id` output:

- `aws_s3_bucket_notification` — the shape varies too much (lambda / sqs / sns /
  eventbridge) to model without a leaky `any`
- `aws_s3_bucket_replication_configuration`
- `aws_s3_bucket_acl` — ACLs are disabled by `BucketOwnerEnforced`

## Migration notes

Moving an existing bucket into this module changes its state addresses, so it needs
`moved` blocks. Three things to get right:

1. **`name` must be byte-identical.** `bucket` is the only ForceNew field on
   `aws_s3_bucket`; a mismatch plans a destroy + recreate of live data. Read every
   migration plan for `must be replaced` before applying.
2. **`aws_s3_bucket_logging` and `aws_s3_bucket_lifecycle_configuration` are
   `count`-gated here**, so their addresses carry a `[0]` index:
   `module.x.aws_s3_bucket_logging.this[0]`.
3. **`aws_s3_bucket_acl` is not moved, it is destroyed** — `BucketOwnerEnforced`
   disables ACLs. Expect it as a removal in the plan.

Two diffs look alarming but are intended: dropping `ignore_changes = [tags]`
reconciles tag drift on first apply, and switching to `BucketOwnerEnforced` shows the
ACL resources being destroyed.

**`BucketOwnerEnforced` breaks writers at runtime, not at plan time.** Any caller
sending an `x-amz-acl` header starts failing with `AccessControlListNotSupported`,
and no Terraform plan will show it. Audit application code before migrating a bucket
that receives uploads.

**Switching AES256 → CMK is not retroactive.** Existing objects keep the key they
were written with; only new writes use the CMK. Every principal reading the bucket
needs `kms:Decrypt` added *first*, or reads break at runtime.

### `phi` has a WRITER-side prerequisite, not just a reader-side one

`phi` forces a CMK, so `s3:x-amz-server-side-encryption` must be `aws:kms` on any
upload that sends the header at all. A client that explicitly sends `AES256` is
denied by `DenyUnencryptedObjectUploads`.

This is easy to miss because the usual advice is "add `kms:Decrypt` to readers." The
readers are the second problem. The first is that **an application hardcoding
`ServerSideEncryption: 'AES256'` on upload will have every write rejected** the
moment its bucket moves to a CMK.

Audit the writers before assigning `phi` to an existing bucket. The fix is normally to
stop sending the header at all and let bucket default encryption apply — which is
also why this module's deny statement tolerates a missing header (see `policy.tf`).

## Inputs

See `variables.tf` — every input carries a description, including the failure mode
it guards against.

## Outputs

`id`, `arn`, `bucket`, `bucket_domain_name`, `bucket_regional_domain_name`,
`hosted_zone_id`.
