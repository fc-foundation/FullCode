terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  # Partial configuration: resource_group_name, storage_account_name,
  # container_name, and key are passed with -backend-config at init time (see
  # .github/workflows/terraform-deploy.yml), from the state backend created by
  # scripts/New-TerraformStateBackend.ps1.
  backend "azurerm" {
    use_oidc         = true
    use_azuread_auth = true
  }
}
