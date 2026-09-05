terraform {
  required_version = ">= 1.5"
}

module "resource_group" {
  source        = "../../modules/naming"
  resource_type = "resource_group"
  environment   = "dev"
  region        = "eastus2"
  instance      = "001"
}

module "virtual_network" {
  source        = "../../modules/naming"
  resource_type = "virtual_network"
  environment   = "dev"
  region        = "eastus2"
  instance      = "001"
}

module "subnet" {
  source        = "../../modules/naming"
  resource_type = "subnet"
  environment   = "dev"
  region        = "eastus2"
  instance      = "001"
}

module "network_security_group" {
  source        = "../../modules/naming"
  resource_type = "network_security_group"
  environment   = "dev"
  region        = "eastus2"
  instance      = "001"
}

module "public_ip" {
  source        = "../../modules/naming"
  resource_type = "public_ip"
  environment   = "dev"
  region        = "eastus2"
  instance      = "001"
}

module "route_table" {
  source        = "../../modules/naming"
  resource_type = "route_table"
  environment   = "dev"
  region        = "eastus2"
  instance      = "001"
}

module "storage_account" {
  source        = "../../modules/naming"
  resource_type = "storage_account"
  environment   = "prod"
  region        = "eastus2"
  instance      = "001"
}

module "key_vault" {
  source        = "../../modules/naming"
  resource_type = "key_vault"
  environment   = "prod"
  region        = "eastus2"
  instance      = "001"
}
