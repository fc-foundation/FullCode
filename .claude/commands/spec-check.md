---
description: Read-only check for drift between a spec and the current code
argument-hint: <feature-name>
---

Find the spec folder under `docs/specs/` matching `*-$1` (e.g. `docs/specs/003-$1`) and read its `current-spec.md`. If no matching folder exists, stop and say so. For each item in its Requirements section, check whether the current code satisfies it.

Report, per requirement: met / partially met / not met / can't tell, with a one-line reason and a file reference where relevant.

This is read-only — do not edit code or the spec. If drift is found, suggest whether the fix is to update the code or update the spec.
