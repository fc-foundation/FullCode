---
description: Plan and implement a feature from its spec
argument-hint: <feature-name>
---

Read `docs/specs/$1.md`. If it doesn't exist, stop and say so — don't guess at requirements.

Enter plan mode. Propose an implementation plan whose steps map back to the spec's Requirements section, and flag anything in Open questions that blocks a step.

On approval, implement the plan. When done:
- Update `docs/specs/$1.md`: set Status to `done` (or `in-progress` if only partially completed), and note any requirement that couldn't be met as written.
- Summarize what changed and where.
