# Terraform Lifecycle Protection

Status: done

## Problem

Terraform resource modules (starting with `terraform/modules/resource-group`) have no safeguard against destructive plans. Removing a resource block, running `terraform destroy`, or changing a `ForceNew` attribute (including any input to the shared naming module — environment, region, instance, workload — since it flows into `name`, which is `ForceNew` for most Azure resource types) would currently destroy-and-recreate or delete real infrastructure with no build-time warning.

## Goals

- Every resource module's managed resource is protected so that Terraform itself refuses any plan/apply that would destroy or replace it — whether from `terraform destroy`, deleting the resource block, or changing a `ForceNew` attribute.
- This protection is the standard pattern for every resource module going forward, not a one-off on a single module.

## Non-goals

- A CI-level policy gate that scans plan output for destroy/replace actions (considered and explicitly not chosen — `lifecycle { prevent_destroy = true }` is the sole mechanism for this spec).
- Protection against `terraform state rm` followed by manual deletion — `prevent_destroy` only guards `terraform plan`/`apply`, not direct state manipulation. Out of scope here.
- Handling partial-destroy scenarios within a single multi-resource module beyond what `prevent_destroy` already provides per-resource.

## Requirements

1. Every `resource` block that manages a real Azure resource in `terraform/modules/*` includes a `lifecycle { prevent_destroy = true }` block.
2. `terraform/modules/resource-group/main.tf`'s `azurerm_resource_group.this` gets this protection now.
3. The pattern is documented (in the module itself, via a short comment, and referenced from `specs/infrastructure-naming.md`) so every future resource module includes it from creation rather than as an afterthought.
4. As a direct consequence of `prevent_destroy` blocking replacement: once a resource is deployed, changing any of its naming-module inputs (`environment`, `region`, `instance`, `workload`) will cause `terraform plan`/`apply` to error rather than silently destroying and recreating the resource. This is the intended behavior, not a defect — such inputs are effectively immutable post-deployment unless someone deliberately removes the lifecycle block first.

## Open questions

- None blocking. Noting for awareness: `prevent_destroy` is a Terraform-native safeguard scoped to `plan`/`apply` — it does not prevent deletion via `terraform state rm` + manual portal/CLI deletion, or via a state migration. If that gap matters later, it would need a separate control (e.g., Azure resource locks), which is out of scope here.
