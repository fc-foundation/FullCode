---
description: Draft or update a feature spec in docs/specs/
argument-hint: <feature-name> [short description]
---

Create or update the spec for `$1`:

- Look for an existing folder under `docs/specs/` matching `*-$1` (e.g. `docs/specs/003-$1`).
  - If found, update its `current-spec.md`.
  - If not found, create a new one: count the existing spec folders directly under `docs/specs/` (folders only — ignore `README.md`/`TEMPLATE.md`), set `<index>` to that count + 1 zero-padded to 3 digits (e.g. `004`), and create `docs/specs/<index>-$1/current-spec.md` from `docs/specs/TEMPLATE.md`.
- Use the rest of the arguments (if any) as the starting description of the problem/goal.
- Fill in Problem, Goals, Non-goals, and Requirements as best you can from what's given.
- Ask up to 3 clarifying questions only if something material is missing or ambiguous — otherwise make reasonable assumptions and note them under Open questions.
- Do not write or edit any code in this command — spec only.
- Leave Status as `draft` unless the user says otherwise.
