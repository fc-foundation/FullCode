# Authenticates with the pipeline's federated managed identity via GitHub
# Actions OIDC. Client, tenant, and subscription IDs come from the
# ARM_CLIENT_ID / ARM_TENANT_ID / ARM_SUBSCRIPTION_ID environment variables —
# no client secret.
provider "azurerm" {
  features {}

  use_oidc = true
}
