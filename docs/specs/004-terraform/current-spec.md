# Terraform

Status: in-progress

## Problem

There is no pipeline that actually deploys Terraform-managed Azure infrastructure. Today `.github/workflows/terraform.yml` only validates formatting and the naming convention against a provider-free example root (`infra/terraform/examples/naming-check`) — it never authenticates to Azure or applies anything real. Meanwhile `infra/terraform/modules/resource-group` (the module for the very first real resource this repo will deploy) and `scripts/New-IdentityResourceGroup.ps1` (which bootstraps a federated, secret-less Azure identity for CI to use — `003-identity-resource-group`, already run successfully against `dev`) exist but aren't wired together: nothing yet uses that identity to run `terraform plan`/`apply` against a live subscription, and there is no remote state backend for such a pipeline to use.

## Goals

- A GitHub Actions pipeline that authenticates to Azure using the existing federated (OIDC) managed identity from `003-identity-resource-group` — no client secret stored in GitHub.
- The pipeline deploys (plans and applies) a dedicated "main" resource group — the one that will hold all future workload resources for an environment — using the existing `infra/terraform/modules/resource-group` module.
- Terraform state lives in a remote `azurerm` backend, bootstrapped by a manual script (same chicken-and-egg reasoning as `003-identity-resource-group`).
- The pipeline is the foundation future environment/workload deployments build on, not a one-off.
- Covers the `dev` environment to start, since that's the only environment with a bootstrapped identity so far.

## Non-goals

- Deploying anything beyond the single "main" resource group in this spec — VNets, subnets, workload resources, etc. are future work building on this pipeline.
- Bootstrapping `test`/`prod` federated identities, state backends, or environments — out of scope until those are needed (already tracked as a follow-up in `003-identity-resource-group`). The bootstrap script and workflow are parameterized so adding them later is configuration, not redesign.
- Changing the existing `fmt-validate`/`naming-check` jobs in `.github/workflows/terraform.yml` — this pipeline is a new, separate workflow.
- Changing `scripts/New-IdentityResourceGroup.ps1` or its federated credential — the state backend gets its own bootstrap script, and a separate read-only PR identity is deferred (see Open questions).
- Auto-applying on merge to `main` — apply is manual-only in this spec.
- Posting plan output as a PR comment — plan output goes to the job log and job summary only.
- Configuring branch protection / required status checks, or GitHub Environment protection rules — existing manual follow-ups from `001-infrastructure-naming` / `003-identity-resource-group`; not re-scoped here.

## Requirements

1. **State backend bootstrap script.** A new manual (human-run) PowerShell script, `scripts/New-TerraformStateBackend.ps1`, following the conventions of `scripts/New-IdentityResourceGroup.ps1` (Az module; all parameters mandatory, no defaults; `-Environment` restricted to `dev`/`test`/`prod`; `-Location` restricted to the regions in `infra/terraform/modules/naming/locals.tf`; idempotent check-before-create; console output and a required `-OutputPath` JSON file). For the given environment it creates or confirms:
   - a dedicated state resource group, `rg-<workload>-<env>-<region>-<instance>` (separate from both the identity resource group and the main resource group);
   - a storage account in it, named per the naming convention's `storage_account` compact scheme (`st<workload><env><region><instance>`, ≤ 24 chars), with blob versioning and soft delete enabled, public blob access disabled, and minimum TLS 1.2;
   - a private blob container named `tfstate`;
   - a `Storage Blob Data Contributor` role assignment for the environment's managed identity (from `003`), scoped to the storage account, so Terraform can use Azure AD auth for state rather than storage account keys (subscription-level `Contributor` does not grant blob data access). The identity is looked up by name/resource group passed as parameters, not re-created.
   - Output: the resource group name, storage account name, container name, and state key needed to configure the backend.
2. **Terraform root per environment.** A deployable root at `infra/terraform/environments/dev` that calls `infra/terraform/modules/resource-group` to create the environment's main resource group, following the existing naming convention: workload `fc`, environment `dev`, region `eastus2`, instance `001` → `rg-fc-dev-eus2-001`. It pins Terraform and the `azurerm` provider consistently with the existing modules (`azurerm ~> 3.0`) and commits its `.terraform.lock.hcl`.
3. **Remote state.** The root's `azurerm` backend points at the storage account/container from requirement 1, with state key `dev.tfstate`, `use_oidc = true` and `use_azuread_auth = true`. Backend values that differ per environment are supplied at `terraform init` time (`-backend-config`) rather than hardcoded in a way that blocks adding `test`/`prod` roots later. State locking uses the backend's built-in blob lease.
4. **OIDC authentication, no stored secret.** Both the `azurerm` provider and backend authenticate with the federated managed identity from `003-identity-resource-group` via native OIDC (`use_oidc = true`), using its client ID, tenant ID, and subscription ID — never a client secret. Jobs that talk to Azure declare `permissions: id-token: write` (plus `contents: read`) and run with `environment: dev` so the GitHub OIDC token's subject (`repo:fc-foundation/FullCode:environment:dev`) matches the federated credential.
5. **Credential and backend wiring as GitHub Environment variables.** The client ID, tenant ID, and subscription ID (from `003`'s `-OutputPath` JSON) and the state backend values (from requirement 1's output) are stored as **variables** (not secrets — none of these are credentials) on the `dev` GitHub Environment, e.g. `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`, `TFSTATE_CONTAINER`. Setting them (`gh variable set --env dev ...`) is a documented setup step of this spec's implementation.
6. **New deploy workflow.** A new workflow, `.github/workflows/terraform-deploy.yml`, separate from `terraform.yml`:
   - **PR plan**: on `pull_request` touching `infra/terraform/environments/**`, `infra/terraform/modules/**`, `infra/policy/**`, or the workflow file itself, runs `fmt -check`, `init` (with the remote backend), `validate`, and `plan` against `infra/terraform/environments/dev`, and writes the plan's human-readable output to the job summary. It never applies.
   - **Manual apply**: on `workflow_dispatch` (with an `environment` input, restricted to `dev` for now), runs `init` → `plan -out` → `apply` of that exact saved plan file within the same run. There is no automatic apply on push/merge.
   - A `concurrency` group per environment ensures at most one plan/apply against a given environment's state at a time.
   - Terraform version matches the existing workflow's `TF_VERSION` (`1.9.8`).
7. **Policy check on the real plan.** Both the PR plan and the manual apply convert the plan to JSON and run `conftest test --policy infra/policy` against it (the same rules `naming-check` uses, which already cover real `azurerm_*` resources); a policy failure fails the job before any apply.
8. **Respects existing safety guardrails.** The resource group module's `lifecycle { prevent_destroy = true }` (`002-terraform-lifecycle-protection`) is left intact. The pipeline has no destroy job and does not use `-target`, `-replace`, `terraform state rm`, or similar to route around it; a plan that would destroy or replace the resource group fails the run.
9. **Idempotent / re-runnable.** Re-running the manual apply against an already-deployed `dev` produces a clean "No changes" plan and succeeds without erroring or drifting. Re-running `scripts/New-TerraformStateBackend.ps1` against an already-bootstrapped environment does not fail or duplicate resources.
10. **Documentation.** `infra/terraform/README.md` describes the one-time bootstrap order for an environment (identity script → state backend script → GitHub Environment variables) and how to trigger plan/apply.

## Open questions

- **State backend location — resolved.** A new, dedicated manual script (`scripts/New-TerraformStateBackend.ps1`) creates its own resource group rather than reusing the identity resource group or extending `003`'s script, so `003` stays single-purpose and `done`.
- **State backend instance numbers**: the resource group can't reuse `000`, because the identity resource group already has the name `rg-fc-dev-eus2-000`. Assuming the script takes mandatory `-ResourceGroupInstance`/`-StorageAccountInstance` parameters (mirroring `003`'s separate instance parameters), with `900` for both. That gives `rg-fc-dev-eus2-900` and `stfcdeveus2900`, and reserves the `9xx` range for platform/bootstrap resources so it never collides with workload instances that count up from `001`. Storage account names are globally unique, so if `stfcdeveus2900` is taken, pick another `9xx` value.
- **PR plan identity — resolved (accepted risk).** The federated subject is scoped to the `dev` GitHub Environment, and `dev` currently has no protection rules or deployment-branch policy. So PR plans run with the same subscription-scoped `Contributor` identity used for apply, and any branch can trigger the manual apply to `dev`. This is accepted for now because the org has a single member and there are no fork PRs. Follow-up: add a separate read-only federated credential (subject `repo:fc-foundation/FullCode:pull_request`, `Reader` plus read-only state-blob access) for PR plans, and/or a deployment-branch policy on `dev`, once there is more than one contributor.
- **Apply trigger — resolved.** Apply is manual only (`workflow_dispatch`), with plan and apply in the same run, so the applied plan is exactly the one that was reviewed in that run's log. Auto-apply on merge to `main` will be reconsidered once the pipeline is trusted.
- **Credential wiring — resolved.** GitHub Environment **variables** on `dev`, not repo-level secrets (requirement 5). Client, tenant, and subscription IDs aren't sensitive, and environment scoping keeps `test`/`prod` values separate when those environments are added.
- **Directory layout — resolved.** One root per environment under `infra/terraform/environments/<env>/`, not a single root switched by `.tfvars`.
- **PR plan scope — resolved.** Yes, `plan` runs on PRs, following the same trigger pattern as `fmt-validate`/`naming-check`, but in the new workflow (requirement 6).
- **Operator permissions for bootstrap**: assuming the person running `New-TerraformStateBackend.ps1` has `Owner` or `User Access Administrator` on the subscription (needed for the role assignment), the same as for `003`'s script.
- **Main resource group tags**: assuming a minimal set (`environment`, `workload`, `managed_by = "terraform"`). A formal tagging convention is out of scope.

## Implementation notes

- **R1: `scripts/New-TerraformStateBackend.ps1`.** Follows `New-IdentityResourceGroup.ps1`'s conventions: every parameter is mandatory, `ValidateSet` is used on environment and region, `Get-RegionAbbreviation` is copied with a keep-in-sync comment, and output is BOM-less JSON.
  - It checks the pipeline identity exists *before* creating anything.
  - It checks the storage account name is globally available before creating it, and fails with a "pick another `-StorageAccountInstance`" message if not.
  - Blob versioning and 30-day blob and container soft delete are reapplied on every run.
  - The container is created through the management plane (`New-AzRmStorageContainer`), so the operator doesn't need a blob data role.
  - The `Storage Blob Data Contributor` assignment reuses the identity script's 5×10s retry loop.
  - Local runner: `.local/Invoke-TerraformStateBackend.ps1` (gitignored). It reads the subscription and identity from `.local/Github-Federated-Identities/dev-identity.jsonc` and writes `dev-tfstate.json` next to it. It passes instance `900`, which gives `rg-fc-dev-eus2-900` / `stfcdeveus2900`, and container `tfstate`.
- **R2–R4, R8: `infra/terraform/environments/dev/`.**
  - Files: `versions.tf` (partial `azurerm` backend with `use_oidc` + `use_azuread_auth`), `providers.tf` (`use_oidc = true`, IDs from `ARM_*` environment variables), `main.tf` (`module "main_resource_group"` → `rg-fc-dev-eus2-001`, tags `environment`/`workload`/`managed_by`), and `outputs.tf`.
  - `.terraform.lock.hcl` is locked to azurerm `3.117.1`, the same version as `modules/resource-group`, for linux_amd64, windows_amd64 and darwin_amd64/arm64.
  - The backend's resource group, storage account, container and key are passed with `-backend-config` at init, so a `test`/`prod` root is a copy of this folder with different locals.
- **R5–R7, R9: `.github/workflows/terraform-deploy.yml`.**
  - One `plan-apply` job, triggered by PRs (on the listed paths) or by `workflow_dispatch` (`environment` choice: `dev`).
  - It runs in the chosen GitHub Environment, with `id-token: write`, a per-environment `concurrency` group, and is skipped for fork PRs.
  - Steps: `fmt -check` → `init` (remote backend) → `validate` → `plan -out` → plan in job summary → `show -json` → conftest `infra/policy` → `apply tfplan.binary` (dispatch only).
  - There is no destroy step, and no `-target`/`-replace`.
  - `terraform.yml` is unchanged. `actionlint` 1.7.7 passes on both workflows.
- **R10:** `infra/terraform/README.md` now covers the layout, the bootstrap order, `gh variable set` commands and how to trigger plan and apply. `scripts/README.md` lists the bootstrap scripts.
- **Verified locally (before any live bootstrap):**
  - `terraform fmt -check` and `validate` pass on the new root, and both new PowerShell scripts parse with zero errors.
  - A read-only `terraform plan` of the root against the live `dev` subscription (local backend override in a scratch copy, operator's `az login`, provider registration skipped) produced `Plan: 1 to add` for `rg-fc-dev-eus2-001`.
  - `conftest test --policy infra/policy` passed 3/3 on that plan's JSON, confirming rule set 2 of `naming.rego` accepts the real resource.
- **State backend bootstrapped (R1, live).** The operator ran `.local/Invoke-TerraformStateBackend.ps1` against `dev`. Checked afterwards with `az`:
  - `rg-fc-dev-eus2-900` and `stfcdeveus2900` exist: TLS 1.2, HTTPS only, no public blob access, versioning on, 30-day blob and container soft delete.
  - The `tfstate` container is private.
  - The only role assignment on the account is `Storage Blob Data Contributor` for the pipeline identity (client ID matches `id-fc-dev-eus2-000`).
  - The instance `900` name was available, so no fallback was needed.
- **GitHub Environment variables set (R5).** The 6 `dev` Environment variables are set: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `TFSTATE_RESOURCE_GROUP=rg-fc-dev-eus2-900`, `TFSTATE_STORAGE_ACCOUNT=stfcdeveus2900` and `TFSTATE_CONTAINER=tfstate`.
- **Pending (why Status is `in-progress`):**
  1. A PR run shows the OIDC + remote-backend plan working.
  2. After merge to `main`, a `workflow_dispatch` apply creates the resource group, and a second dispatch shows `No changes.` (R9).
- Tracked in [issue #4](https://github.com/fc-foundation/FullCode/issues/4) (FullCode Site Project, In progress).
