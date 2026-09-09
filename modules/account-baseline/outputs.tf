output "ebs_encryption_regions" {
  description = "Regions where EBS default encryption is enabled by this module"
  value       = sort(var.ebs_encryption_regions)
}

output "s3_account_public_access_block_managed" {
  description = "Whether this module manages the account-wide S3 public access block. False means the account's setting is unmanaged, NOT that public access is blocked."
  value       = var.manage_s3_account_public_access_block
}

output "iam_password_policy_managed" {
  description = "Whether this module manages the account IAM password policy"
  value       = var.manage_iam_password_policy
}
