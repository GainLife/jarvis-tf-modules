terraform {
  # 1.2+ for lifecycle preconditions. Both consumer repos are well past this.
  required_version = ">= 1.2"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Deliberately a lower bound, not a pin: a module that pins the provider
      # fights its callers. Both consumers are on ~> 6.0.
      version = ">= 6.0"
    }
  }
}
