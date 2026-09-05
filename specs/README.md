# Specs

One markdown file per feature, named `specs/<feature-name>.md`, following [TEMPLATE.md](TEMPLATE.md).

Workflow:
1. `/spec <feature-name>` — draft or update the spec.
2. `/implement <feature-name>` — plan against the spec (Plan Mode), then implement on approval.
3. `/spec-check <feature-name>` — read-only check for drift between the spec and the current code.

Specs stay in the repo as the source of truth; update them when requirements change rather than letting them go stale.
