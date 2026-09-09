terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.x for the resource-level `region` argument. It lets EBS default encryption
      # cover every region from a single for_each instead of one provider alias per
      # region, which is the same reason the org-wide GuardDuty
      # configuration needs 6.x.
      version = ">= 6.0"
    }
  }
}
