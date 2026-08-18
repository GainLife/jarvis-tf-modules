# ─────────────────────────────────────────────────────────────────────────────
# Baseline bucket policy.
#
# This file exists because of a specific, measured defect in the consumer repos:
# 22 of 33 hand-written SecureTransport deny statements scope Resource to
# "${bucket_arn}/*" only. That covers objects but NOT the bucket itself, leaving
# ListBucket / GetBucketPolicy / GetBucketLocation reachable over plaintext HTTP.
#
# Here the statement is emitted by the module, covers both ARNs, and cannot be
# removed by a caller — var.extra_policy_json merges IN via
# source_policy_documents, it does not replace.
# ─────────────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "this" {
  # Caller statements merge in; they cannot displace the baseline below.
  source_policy_documents = var.extra_policy_json

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    # BOTH ARNs — the bucket and its objects. See the header comment.
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  dynamic "statement" {
    for_each = local.profile.deny_old_tls ? [1] : []

    content {
      sid     = "DenyOutdatedTLS"
      effect  = "Deny"
      actions = ["s3:*"]

      resources = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*",
      ]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "NumericLessThan"
        variable = "s3:TlsVersion"
        values   = ["1.2"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.profile.deny_unencrypted_put ? [1] : []

    content {
      sid       = "DenyUnencryptedObjectUploads"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.this.arn}/*"]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "StringNotEquals"
        variable = "s3:x-amz-server-side-encryption"
        values   = [local.sse_algorithm]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.this.json

  # The public-access block must exist before a policy is attached, so
  # block_public_policy is already in force when the policy lands.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
