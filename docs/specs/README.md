# Specs

One folder per feature, named `docs/specs/<index>-<feature-name>/`, containing a `current-spec.md` that follows [TEMPLATE.md](TEMPLATE.md). `<index>` is a zero-padded, incrementing 3-digit number assigned when the spec is first created (based on how many spec folders already exist).

Workflow:
1. `/spec <feature-name>` — draft or update the spec.
2. `/implement <feature-name>` — plan against the spec (Plan Mode), then implement on approval.
3. `/spec-plan <feature-name>` — save the approved plan into `<spec-folder>/plan.md` and track it on the repo's GitHub Project board.
4. `/spec-check <feature-name>` — read-only check for drift between the spec and the current code.

Specs stay in the repo as the source of truth; update them when requirements change rather than letting them go stale.
