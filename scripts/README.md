# scripts

Development, build, and deployment helper scripts.

- `New-IdentityResourceGroup.ps1`: manual bootstrap of an environment's pipeline managed identity and its GitHub OIDC federation (`docs/specs/003-identity-resource-group`).
- `New-TerraformStateBackend.ps1`: manual bootstrap of an environment's Terraform remote state storage account and container. Run it after `New-IdentityResourceGroup.ps1` (`docs/specs/004-terraform`).
- `Test-NamingConvention.ps1`: runs the conftest naming-convention check locally, mirroring the `naming-check` CI job.
