output "ebs_encryption_regions" {
  description = "Regions where this module enables EBS default encryption. Deduplicated and sorted, so it reflects what is actually applied rather than what was passed in."
  value       = sort(distinct(var.ebs_encryption_regions))
}

output "s3_account_public_access_block_managed" {
  description = <<-DESC
    Whether this module manages the account-wide S3 public access block.

    FALSE DOES NOT MEAN PUBLIC ACCESS IS BLOCKED, and it does not mean the account has
    no block. It means this module is not managing the setting -- whatever the account
    already had remains in force, managed elsewhere or not at all. Check the account
    directly rather than inferring posture from this value.
  DESC
  value       = var.manage_s3_account_public_access_block
}

output "iam_password_policy_managed" {
  description = "Whether this module manages the account IAM password policy. False means the account keeps whatever policy it already had, which may be the AWS default."
  value       = var.manage_iam_password_policy
}
