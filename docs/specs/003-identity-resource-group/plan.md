# Implementation Plan: Identity Resource Group

> Reconstructed from `current-spec.md`'s Implementation notes and the shipped
> script, since the original Plan Mode session predates this conversation and
> its plan text isn't available to save verbatim.

## Approach

Ship a single manual PowerShell script, `scripts/New-IdentityResourceGroup.ps1`,
that an operator runs once per environment (`dev`, `test`, `prod`) to bootstrap
the Azure identity that GitHub Actions needs to authenticate via OIDC before
Terraform can run. Not automated via CI/Terraform (chicken-and-egg: Terraform's
own pipeline identity can't be created by Terraform before it exists).

## Steps

1. **Parameterize by environment and workload — all mandatory.** `-Workload`
   (no default) and `-Environment` restricted via `ValidateSet` to
   `dev`/`test`/`prod`; every other parameter is mandatory too, with no
   defaults: `-SubscriptionId`, `-Location` (`ValidateSet` across the 9 Azure
   public-cloud US regions in `locals.tf`'s `region_abbreviations` map),
   `-ResourceGroupInstance` and `-IdentityInstance` (two separate values,
   replacing a single shared `-Instance`; they may be equal since the
   `rg-`/`id-` prefix already keeps the two names distinct),
   `-GithubFederationName` (base name for the federated credential, combined
   with `-Environment`), `-Repository`, `-OutputPath`. Requiring every
   parameter explicitly (revised from the original optional-with-defaults
   design) means an operator can't silently inherit a wrong default for a
   naming input.

2. **Replicate naming convention by hand.** Since
   `infra/terraform/modules/naming` can't be invoked from a standalone script,
   hand-copy the relevant slice of `infra/terraform/modules/naming/locals.tf`'s
   CAF pattern via a `Get-RegionAbbreviation` function: workload from
   `-Workload`, region from a 9-entry US-region map (`eastus` → `eus`,
   `eastus2` → `eus2`, `centralus` → `cus`, `northcentralus` → `ncus`,
   `southcentralus` → `scus`, `westcentralus` → `wcus`, `westus` → `wus`,
   `westus2` → `wus2`, `westus3` → `wus3`), giving e.g.
   `rg-fc-dev-eus2-<ResourceGroupInstance>` and
   `id-fc-dev-eus2-<IdentityInstance>`. Comment the duplication so it's kept
   in sync, same precedent as `infra/policy/naming.rego` (also updated to the
   same 9-region set). The two instance values must each be 3-digit numbers
   to match `naming.rego`'s `[0-9]{3}` instance-segment regex, but they don't
   need to differ from each other.

3. **Resource group (idempotent).** `Get-AzResourceGroup` first; only
   `New-AzResourceGroup` if it doesn't exist.

4. **User-assigned managed identity (idempotent).** Same check-then-create
   pattern with `Get-/New-AzUserAssignedIdentity`.

5. **GitHub OIDC federated credential (idempotent + self-healing).**
   `Get-AzFederatedIdentityCredential`; if missing, create it named
   `<GithubFederationName>-<Environment>` with issuer
   `https://token.actions.githubusercontent.com`, audience
   `api://AzureADTokenExchange`, subject
   `repo:<owner/repo>:environment:<environment>`. If it exists but has
   drifted (issuer/subject mismatch), `Update-AzFederatedIdentityCredential`
   in place rather than failing. The `environment:` subject form is
   deliberately branch-agnostic — which branches may deploy to a given
   environment is controlled by that GitHub Environment's own "Deployment
   branches and tags" protection rule, not by this script.

6. **RBAC assignment with replication retry.** Check for an existing
   Contributor role assignment at subscription scope; if absent, create one,
   retrying up to 5 times (10s apart) to absorb Azure AD replication lag for a
   freshly created identity's service principal — a real failure mode of
   `New-AzRoleAssignment`, not speculative hardening.

7. **Emit pipeline configuration values.** Print environment, resource group,
   identity name, client ID, principal ID, tenant ID, and subscription ID to
   the console (`Format-List`), and also write them as BOM-less UTF-8 JSON to
   the required `-OutputPath` (same BOM fix precedent as
   `scripts/Test-NamingConvention.ps1`) for feeding into
   `gh secret set` / `gh variable set`.

8. **Print the manual GitHub-side follow-up.** The federated subject only
   matches pipeline runs once a GitHub Environment named `dev`/`test`/`prod`
   exists in the repo's Settings > Environments — print a reminder since the
   script intentionally doesn't create these itself (non-goal).

## Verification

- Static validation: `[System.Management.Automation.Language.Parser]::ParseFile`
  (zero errors) plus manual review of the `Az` cmdlets used.
- Full end-to-end run confirmed against the live `dev` subscription: resource
  group `rg-fc-dev-eus2-000`, managed identity `id-fc-dev-eus2-000`, its
  federated credential, and the Contributor role assignment were all created
  successfully via `.local/Invoke-IdentityResourceGroup.ps1`, with output
  captured to `.local/Github-Federated-Identities/dev-identity.json`. Sign-in
  hit two Windows PowerShell 5.1-specific `Connect-AzAccount` issues along the
  way — a `get_SerializationSettings` assembly-mismatch error (WAM broker has
  no assembly isolation under Windows PowerShell 5.1, unlike PowerShell 7) and
  a blank WAM account picker — worked around via `-UseDeviceAuthentication`.
  Spec status is now `done`. `test`/`prod` runs are still outstanding.

## Follow-ups (outside this script)

- Run `.local/Invoke-IdentityResourceGroup.ps1` (or equivalent) for `test` and
  `prod` when those environments are needed — only `dev` has been bootstrapped
  so far.
- Done: `-ResourceGroupInstance`/`-IdentityInstance` reconciled to 3-digit
  numbers matching `infra/policy/naming.rego`'s `[0-9]{3}` instance-segment
  regex (currently `000`/`000` — equal is allowed, see current-spec.md Open
  questions).
- Revisit the Contributor/subscription-scope RBAC assumption toward a
  narrower scope once real workloads exist and the actual resource footprint
  is known.
- Revisit adding a required-reviewer protection rule on the `prod` GitHub
  Environment once a second org member exists (see current-spec.md
  Implementation notes — GitHub Environments themselves already exist).
