# Terragrunt Configuration for default-cluster

include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "${get_repo_root()}/tofu/modules/aws-eks"
}
