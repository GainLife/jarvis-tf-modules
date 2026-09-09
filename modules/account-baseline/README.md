# account-baseline

Settings every AWS account should carry before anything is deployed into it.

```hcl
module "baseline" {
  source = "git::https://github.com/GainLife/jarvis-tf-modules.git//modules/account-baseline?ref=account-baseline/v1.0.0"
}
```

No required inputs.

## What it does

| | Scope | Default |
|---|---|---|
| EBS default encryption | per region | on, 17 regions |
| S3 public access block | account-wide | **off** — see below |
| IAM password policy | account-wide | on |

## The S3 block is off by default, on purpose

Account-level S3 settings **override per-bucket ones**. So an account-wide block breaks
a bucket that deliberately allows a public policy, and nothing about that bucket's own
configuration will explain why.

Some accounts legitimately serve public S3 objects. Defaulting the block to on would
mean adopting this module silently breaks them — the wrong behaviour for a module meant
to be safe to apply.

**Turn it on for any account that does not serve public objects**, which is most of
them:

```hcl
module "baseline" {
  source = "..."
  manage_s3_account_public_access_block = true
}
```

For an account that serves one public bucket but wants the rest of the protection, keep
the block on and relax the single flag rather than abandoning all four:

```hcl
module "baseline" {
  source = "..."

  manage_s3_account_public_access_block = true
  s3_block_public_policy                = false  # this account serves a public bucket
}
```

Per-bucket blocks remain the primary control. This is defence in depth for the case
where someone creates a bucket without one.

## Turning either account-wide setting off is not a no-op

Both account-level resources carry `prevent_destroy`.

Flipping `manage_s3_account_public_access_block` or `manage_iam_password_policy` from
true to false does not "stop managing" — it makes Terraform **destroy** the setting,
re-allowing what the block prevented, or reverting the password policy to AWS defaults.
That is a posture change that reads as a routine resource removal in a plan.

`prevent_destroy` makes that fail the plan instead, so it has to be a decision. To
genuinely stop managing a setting without changing it, remove it from state:

```
terraform state rm 'module.baseline.aws_s3_account_public_access_block.this[0]'
```

Note this also means `terraform destroy` on a consumer config will fail while these are
managed — deliberate for a long-lived account, worth knowing for a throwaway one.

## EBS default encryption only affects NEW volumes

Existing volumes cannot be encrypted in place; there is no API for it. They stay
unencrypted until their instances are replaced.

Do not treat applying this module as remediation of anything already running. A volume
whose instance cannot be replaced stays unencrypted indefinitely, and that case does
occur in practice.

**The encryption key is not managed here.** `aws_ebs_default_kms_key` is deliberately
not set, so whatever the account already has stays in force — the AWS-managed `aws/ebs`
key if nothing was configured, or an existing customer-managed key if one was.

That matters because a CMK carries a well-known failure mode: Auto Scaling launches
volumes through a service-linked role, and unless that role holds `kms:CreateGrant` on
the key, launches begin failing — surfacing as an ASG that cannot scale rather than a
Terraform error. This module neither introduces that risk nor protects against it. If an
account already has a CMK default, verify the grant.

## What it deliberately does not do

**AWS Config.** Bills per configuration item and per rule evaluation, and it belongs
with a delegated security-admin account owning Config history org-wide. An org-level
recorder there beats one per account here.

**Cross-account log, backup and monitoring wiring.** The target accounts do not exist
yet, so there are no ARNs to point at. Adding variables now would fix an interface
before it is designed.

**Provider `default_tags`.** A module cannot set them — they are provider configuration.
The consumer must declare them:

```hcl
provider "aws" {
  default_tags {
    tags = {
      App         = "Example"
      Environment = "<purpose>"
    }
  }
}
```

Called out because a reader could reasonably assume a baseline module handles tagging.
It cannot.

## Why the region list is static

`var.ebs_encryption_regions` is a literal list, not `data "aws_regions"`. Opting into a
new region should be a conscious edit, not silent resource churn the next time someone
enables one.

EBS default encryption is a free account setting, so covering idle regions costs nothing
— and an idle region is exactly where an unencrypted volume appears with nobody
watching.

## Requirements

AWS provider `>= 6.0`, for the resource-level `region` argument. Without it this would
need one provider alias per region.
