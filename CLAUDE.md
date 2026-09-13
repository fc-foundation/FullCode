# FullCode

FullCode Network Foundation and Site.

## Spec-driven development

Specs live in `docs/specs/<index>-<feature-name>/current-spec.md`, one folder per feature (see `docs/specs/README.md` and `docs/specs/TEMPLATE.md`).

Workflow:
- `/spec <feature-name>` — draft or update a spec.
- `/implement <feature-name>` — enter Plan Mode against the spec, then implement on approval.
- `/spec-plan <feature-name>` — save the approved plan into the spec's folder and track it on the repo's GitHub Project board.
- `/spec-check <feature-name>` — read-only drift check between spec and code.

Specs are the source of truth: update them when requirements change instead of letting them drift from the code.
