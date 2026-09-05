---
description: Draft or update a feature spec in specs/
argument-hint: <feature-name> [short description]
---

Create or update `specs/$1.md`:

- If `specs/$1.md` doesn't exist, create it from `specs/TEMPLATE.md`.
- Use the rest of the arguments (if any) as the starting description of the problem/goal.
- Fill in Problem, Goals, Non-goals, and Requirements as best you can from what's given.
- Ask up to 3 clarifying questions only if something material is missing or ambiguous — otherwise make reasonable assumptions and note them under Open questions.
- Do not write or edit any code in this command — spec only.
- Leave Status as `draft` unless the user says otherwise.
