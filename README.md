# jarvis-tf-modules

Shared, secure-by-default Terraform modules for Jarvis infrastructure.

Consumed by [`jarvis-infrastructure`](https://github.com/GainLife/jarvis-infrastructure) and
[`jarvis-global-infrastructure`](https://github.com/GainLife/jarvis-global-infrastructure).

## Why this repo is public

Terraform Cloud runs `terraform init` in its own environment, where it is an anonymous git
client. A public repo clones over `git::https://` with no credential, which removes the need
for an org-level SSH key registered against every workspace. Internal visibility does *not*
achieve this — to an unauthenticated client, internal and private are indistinguishable.

## Contributing: this repo is world-readable

Because the credential-free clone depends on public visibility, **nothing
environment-specific may be committed here** — in module code, examples, or documentation:

- no AWS account IDs
- no bucket names, ARNs, or resource identifiers
- no internal hostnames, IPs, or CIDR blocks

Modules must be generic; everything identifying belongs in the calling repository. The usual
way this gets broken is pasting a real resource name into a README example — use obvious
placeholders instead.

## Versioning

Tags are path-prefixed per module so each versions independently:

```
s3-bucket/v1.0.0
```

Consumers pin an exact tag. No floating refs, no branch names:

```hcl
module "example" {
  source = "git::https://github.com/GainLife/jarvis-tf-modules.git//modules/s3-bucket?ref=s3-bucket/v1.0.0"
  # ...
}
```

## Modules

| Module | Status |
|---|---|
| `s3-bucket` | in development |
