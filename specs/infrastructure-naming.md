# Infrastructure Naming

Status: done

## Problem

Terraform specs in this repo will provision Azure resources (starting with the network foundation), but there is no defined naming convention and no automated way to enforce one. Without enforcement, resource names will drift, become inconsistent across environments, and make resources harder to identify, filter, and manage as the footprint grows.

## Goals

- Adopt Microsoft's Cloud Adoption Framework (CAF) recommended Azure resource naming pattern as the repo's naming standard.
- Provide a single shared Terraform naming module that generates conforming names, so resource modules don't hand-roll names.
- Provide an automated CI check that hard-fails the pipeline when a provisioned resource's name doesn't conform to the convention.
- Cover the `dev`, `test`, and `prod` environments from the start.

## Non-goals

- Renaming any existing Azure resources (none exist yet — this repo is greenfield).
- Enforcing tag conventions or other governance policies (separate concern, possible future spec).
- Naming conventions for non-Azure resources.

## Requirements

1. **Standard pattern.** For resource types that allow hyphens, the naming module generates names matching CAF's recommended pattern:
   `<resource-type-abbr>-<workload>-<environment>-<region-abbr>-<instance>`
   e.g. `rg-fc-prod-eus2-001`, `vnet-fc-dev-eus2-001`, `nsg-fc-test-eus2-001`.

2. **Compact pattern for restricted resource types.** For resource types with restricted character sets (lowercase alphanumeric only, no hyphens, globally unique, and/or a short max length — e.g. storage accounts, Key Vault), the naming module generates a compact form of the same components, lowercased and truncated to fit the resource type's max length:
   `<resource-type-abbr><workload><environment><region-abbr><instance>`
   e.g. `stfcprodeus2001`.

3. **Workload token.** The workload/application token is `fc` (FullCode).

4. **Environment tokens.** Supported environments are `dev`, `test`, and `prod`.

5. **Region abbreviations.** The naming module maintains an explicit map from full Azure region names to short codes (e.g. `eastus2` → `eus2`) for every region actually in use in this repo, rather than deriving abbreviations implicitly.

6. **Resource-type abbreviations.** The naming module maintains a lookup table of resource-type abbreviations matching Microsoft's published CAF recommended abbreviations (e.g. `rg` = resource group, `vnet` = virtual network, `snet` = subnet, `nsg` = network security group, `pip` = public IP address, `rt` = route table). The table starts with the network-foundation resource types this repo provisions first and is extended as new resource types are added.

7. **Single source of truth.** All Terraform resource modules in this repo obtain resource names by calling the shared naming module rather than hardcoding or ad-hoc-constructing names.

8. **Instance numbering.** The naming module accepts an instance number input (zero-padded, e.g. `001`) rather than generating one automatically, so callers control disambiguation when multiple instances of the same resource type/environment/region combination exist.

9. **CI enforcement (hard fail).** A CI check validates that every resource name in a Terraform plan conforms to the convention (via the naming module's patterns and the resource-type/region/environment tables) and fails the pipeline — blocking the PR — on any non-conforming name.

## Open questions

- Which Azure region(s) are in scope initially? Assuming `eastus2` (`eus2`) as the only region for now; the region-abbreviation map should be extended when others are added.
- Should the CI check be implemented as a tflint custom ruleset or as a Conftest/OPA policy against `terraform show -json`? Resolved: Conftest/OPA — a single static binary with no toolchain to install, versus tflint custom rules which require a compiled Go plugin.
- Should resource names accept a free-text "purpose" segment beyond CAF's base pattern (e.g. distinguishing multiple VNets in the same environment/region)? Assuming the `instance` segment covers this for now.

## Implementation notes

- `terraform/modules/naming` is the shared module (single source of truth); `terraform/modules/resource-group` is an example consumer showing the calling pattern every future resource module follows.
- `terraform/examples/naming-check` is a provider-free root that exercises the naming module for every resource type in the abbreviation table, so CI can plan it with zero Azure credentials. `policy/naming.rego` checks its output today, and separately includes a dormant rule set (keyed on `resource_changes[].change.after.name`) that will apply automatically once a real environment root with actual `azurerm_*` resources exists — no policy changes needed then.
- `.github/workflows/terraform.yml` runs `fmt`/`validate` across all three Terraform directories, then plans `naming-check` and runs `conftest test` against it, hard-failing the job on any non-conforming name. Verified locally: the generated names match the expected CAF patterns exactly, and Conftest both passes on valid names and fails (exit 1) on a deliberately corrupted name.
- **Manual follow-up required**: the workflow fails its own CI check on violation, but that only blocks a PR from merging once `fmt-validate` and `naming-check` are added as required status checks under branch protection for `main` in repo Settings — a one-time manual step outside this change.
- Every resource module also includes a `lifecycle { prevent_destroy = true }` block on its managed resource(s) — see [[terraform-lifecycle-protection]]. This has a direct interaction with naming: since `prevent_destroy` blocks replacement too, changing a deployed resource's naming-module inputs (environment/region/instance/workload) will error at plan time instead of destroying and recreating it.
