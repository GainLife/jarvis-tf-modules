# Throwaway module used once to prove Terraform Cloud can clone this repo
# anonymously over git::https:// (no SSH key, no credential).
#
# Delete after the check passes — see Task 0 of
# jarvis-infrastructure docs/superpowers/plans/2026-08-18-s3-bucket-module-standards.md

output "ok" {
  value = true
}
