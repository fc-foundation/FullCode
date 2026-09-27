# Terraform Documentation

## Layout

| Path | Purpose |
| --- | --- |
| `modules/naming` | CAF naming convention (`docs/specs/001-infrastructure-naming`). |
| `modules/resource-group` | Resource group module, with `prevent_destroy` (`docs/specs/002-terraform-lifecycle-protection`). |
| `examples/naming-check` | Provider-free root used by `.github/workflows/terraform.yml` to test the naming convention. |
| `environments/<env>` | Deployable root per environment, with remote state. Deployed by `.github/workflows/terraform-deploy.yml` (`docs/specs/004-terraform`). |

## Bootstrapping an environment (one-time, manual)

Terraform can't create its own pipeline identity or state backend, so each environment is bootstrapped by hand, in this order:

1. **Pipeline identity:** run `scripts/New-IdentityResourceGroup.ps1` (`docs/specs/003-identity-resource-group`). It creates `rg-fc-<env>-<region>-000`, which contains a managed identity federated to the `<env>` GitHub Environment and assigned Contributor on the subscription.
2. **State backend:** run `scripts/New-TerraformStateBackend.ps1`. It creates `rg-fc-<env>-<region>-900`, which contains the storage account `stfc<env><region>900` and a `tfstate` container. It also assigns the identity from step 1 Storage Blob Data Contributor on that storage account.
3. **GitHub Environment variables:** set these on the `<env>` environment. They are variables, not secrets, because none of them are credentials. Take the values from the JSON outputs of steps 1 and 2:

   ```sh
   gh variable set AZURE_CLIENT_ID         --env dev --body <ClientId>
   gh variable set AZURE_TENANT_ID         --env dev --body <TenantId>
   gh variable set AZURE_SUBSCRIPTION_ID   --env dev --body <SubscriptionId>
   gh variable set TFSTATE_RESOURCE_GROUP  --env dev --body <ResourceGroupName>
   gh variable set TFSTATE_STORAGE_ACCOUNT --env dev --body <StorageAccountName>
   gh variable set TFSTATE_CONTAINER       --env dev --body <ContainerName>
   ```

## Plan and apply

- **Plan:** runs automatically on PRs that touch `infra/terraform/environments/**`, `infra/terraform/modules/**` or `infra/policy/**`. The plan appears in the job summary, and the plan JSON is checked against `infra/policy` with conftest. PR runs never apply.
- **Apply:** go to *Actions → Terraform Deploy → Run workflow* and pick the environment. The run plans, runs the policy check, then applies that exact plan. `workflow_dispatch` only shows up once the workflow file is on `main`.
- Re-running apply against an environment that's already deployed should report `No changes.`

To run a plan locally, sign in with `az login` and pass the same `-backend-config` values:

```sh
cd infra/terraform/environments/dev
terraform init \
  -backend-config="resource_group_name=<TFSTATE_RESOURCE_GROUP>" \
  -backend-config="storage_account_name=<TFSTATE_STORAGE_ACCOUNT>" \
  -backend-config="container_name=<TFSTATE_CONTAINER>" \
  -backend-config="key=dev.tfstate"
ARM_USE_OIDC=false ARM_SUBSCRIPTION_ID=<SubscriptionId> terraform plan
```

Your own account needs Storage Blob Data Reader (or Contributor) on the state storage account for this to work, because the backend uses Azure AD auth.

## References

[OIDC Implementation](https://thomasthornton.cloud/deploy-terraform-to-azure-with-oidc-and-github-actions/)

[Terraform - GitHub](https://github.com/Azure-Samples/terraform-github-actions)
