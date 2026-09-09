# account-baseline

Settings every AWS account should have before anything is deployed into it. §4.5 of the
multi-account spec;

```hcl
module "baseline" {
  source = "git::https://github.com/GainLife/jarvis-tf-modules.git//modules/account-baseline?ref=account-baseline/v1.0.0"
}
```

No required inputs. The defaults are the intended posture for a normal account.

## What it does

| | Scope | Notes |
|---|---|---|
| EBS default encryption | per region | 17 enabled regions by default |
| S3 public access block | account-wide | overrides per-bucket settings |
| IAM password policy | account-wide | compliance control; see below |

## Two things that will surprise you

**EBS default encryption only affects NEW volumes.** Existing volumes cannot be
encrypted in place — there is no API for it. They stay unencrypted until their instances
are replaced. Do not treat applying this module as remediation of anything already
running. A volume whose instance cannot be replaced stays unencrypted indefinitely,
and that case does occur in practice.

**The S3 block is account-wide and overrides per-bucket settings.** A bucket that
deliberately allows a public policy stops working the moment the account blocks it, and
nothing about the bucket's own configuration explains why.

There is a live case. One consumer account serves a public website bucket whose own policy sets
`block_public_policy = false` on purpose. That account needs:

```hcl
module "baseline" {
  source = "..."

  # this account serves a public website bucket; the account-wide block would
  # override that bucket's own block_public_policy = false and break it.
  s3_block_public_policy = false
}
```

Set the narrowest flag rather than `manage_s3_account_public_access_block = false` — the
other three protections are still worth having.

## What it deliberately does not do

**AWS Config.** Bills per configuration item and per rule evaluation, and it is the remit of a
delegated security admin account that owns Config history org-wide. An org-level
recorder there beats one per account here.

**Cross-account log, backup and monitoring wiring.** The spec lists it in the baseline,
but the target accounts do not exist yet, so there are no ARNs to point at. Adding variables now would ship an interface guessed rather than designed. It lands
in a later version.

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

This is called out because a reader could reasonably assume this module handles it. It cannot.

## Why the region list is static

`var.ebs_encryption_regions` is a literal list, not `data "aws_regions"`. Opting into a
new region should be a conscious edit, not silent resource churn the next time someone
enables one. Same reasoning as
the org-wide GuardDuty configuration in this estate.

EBS default encryption is a free account setting, so covering idle regions costs nothing
— and an idle region is exactly where an unencrypted volume appears with nobody
watching.

## Requirements

AWS provider `>= 6.0`, for the resource-level `region` argument. Without it this would
need one provider alias per region.
