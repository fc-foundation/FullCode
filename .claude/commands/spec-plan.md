---
description: Save a spec's approved implementation plan into its folder and track it on the repo's GitHub Project board
argument-hint: <feature-name>
---

Find the spec folder under `docs/specs/` matching `*-$1` (e.g. `docs/specs/003-$1`). If no matching folder exists, stop and say so.

1. Write the most recently approved implementation plan for this spec (from Plan Mode) into `<spec-folder>/plan.md`, verbatim.
2. Determine this repo's owner/name (e.g. via `git remote get-url origin` or `gh repo view --json owner,name`), then find the GitHub Project (v2) board linked to it — query the repository's `projectsV2` connection (`gh api graphql`) or cross-check `gh project list --owner <owner>` against this repo.
   - If none is linked, say so and stop — don't create a new project.
   - If more than one is linked, ask which one to use.
3. Add an item for this plan to that project board: `gh project item-create <project-number> --owner <owner> --title "<feature-name>: plan" --body "<short plan summary, and the path to plan.md>"`.
4. Report the plan file's path and the project item created.

This creates content visible to others on the GitHub Project board — confirm with the user before creating the item unless they already clearly asked for this specific spec.
