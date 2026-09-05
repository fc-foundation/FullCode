# FullCode

FullCode Network Foundation and Site.

## Spec-driven development

Specs live in `docs/specs/`, one markdown file per feature (see `docs/specs/README.md` and `docs/specs/TEMPLATE.md`).

Workflow:
- `/spec <feature-name>` — draft or update a spec.
- `/implement <feature-name>` — enter Plan Mode against the spec, then implement on approval.
- `/spec-check <feature-name>` — read-only drift check between spec and code.

Specs are the source of truth: update them when requirements change instead of letting them drift from the code.
