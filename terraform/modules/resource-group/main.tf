module "naming" {
  source = "../naming"

  resource_type = "resource_group"
  environment   = var.environment
  region        = var.region
  instance      = var.instance
}

resource "azurerm_resource_group" "this" {
  name     = module.naming.name
  location = var.region
  tags     = var.tags

  # Every resource module in terraform/modules/* must include this: it makes
  # Terraform refuse any plan/apply that would destroy or replace this
  # resource, including replacement triggered by changing a naming-module
  # input (environment/region/instance/workload) after deployment.
  lifecycle {
    prevent_destroy = true
  }
}
