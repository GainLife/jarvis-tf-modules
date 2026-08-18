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
s3-bucket/v1.3.0
```

Consumers pin an exact tag. No floating refs, no branch names:

```hcl
module "example" {
  source = "git::https://github.com/GainLife/jarvis-tf-modules.git//modules/s3-bucket?ref=s3-bucket/v1.3.0"
  # ...
}
```

## Modules

| Module | Latest tag | Docs |
|---|---|---|
| `s3-bucket` | `s3-bucket/v1.3.0` | [modules/s3-bucket](modules/s3-bucket/README.md) |

## Validating a change

`examples/validate` exercises every `s3-bucket` profile and each dynamic block, so a
shape error surfaces here rather than in a consumer repo. It is never applied against
a real account:

```bash
cd examples/validate
terraform init -backend=false
terraform validate
```

To plan it (still no real account — the provider is mocked), isolate it from any
ambient AWS profile:

```bash
AWS_PROFILE= AWS_ACCESS_KEY_ID=mock AWS_SECRET_ACCESS_KEY=mock AWS_REGION=us-east-1 \
AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null \
terraform plan
```
