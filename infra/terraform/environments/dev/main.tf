locals {
  environment = "dev"
  region      = "eastus2"
}

# The environment's main resource group: holds all future workload resources
# for dev.
module "main_resource_group" {
  source = "../../modules/resource-group"

  environment = local.environment
  region      = local.region
  instance    = "001"

  tags = {
    environment = local.environment
    workload    = "fc"
    managed_by  = "terraform"
  }
}
