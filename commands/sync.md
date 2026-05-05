---
description: After a PRD edit, seed a new milestone-update folder for the chosen module, aligned to the latest PRD
---

The user has edited one or more PRD files (`prd/_index.md` or `prd/<module>.md`) and wants a new implementation milestone that lines up with the new product spec.

## Setup

Resolve the active feature folder by reading `.super-manus/active`. The folder is `docs/super-manus/<that-name>/`. If `.super-manus/active` is missing or empty, tell the user there is no active feature and suggest `/super-manus:start <name>` first; then stop.

If `<feature>/prd/` is not a directory, tell the user this command only works on v0.2 features (started with the v0.2 `/super-manus:start`); then stop.

## Pick module + update name

If the user passed a module name as the argument (e.g. `/super-manus:sync api`), use it. Otherwise, list the modules in `<feature>/prd/_index.md ## Modules` (or fall back to listing files in `<feature>/prd/`) and ask the user **once**: "Which module is this update for?" — multiple choice.

Then ask the user **once** for an update name: "Short kebab-case name for this update (e.g. `add-tag-search`, `fix-pagination`)". The update name must match `^[a-z0-9][a-z0-9-]*$`.

## Drift check

Before scaffolding, read `<feature>/prd/<module>.md`:

- Skim `## Surface`, `## Constraints`, `## Out of scope`. If the user described an intent that conflicts with `## Out of scope`, or appears to introduce a capability not declared in `## Surface`, append one row to `<feature>/prd_drift.md`:
  ```
  | <YYYY-MM-DD> | <module> | <one-line conflict description> | pending |
  ```
  Then tell the user: "Drift detected — the intent looks outside the current PRD. Two paths: revert the intent, or run `/super-manus:prd-update <module>` first to update the PRD, then re-run `/super-manus:sync <module>`."
  Stop. Do not scaffold the update folder.

If no drift, continue.

## Scaffold

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sm-update.sh" "<module>" "<update-name>"
```

Surface the script's stderr verbatim if it exits non-zero.

The script creates `<feature>/impl/<module>/<YYYY-MM-DD>-<update-name>/` with `task_plan.md`, `findings.md`, `progress.md`, and an empty `tasks/` subfolder, all seeded from templates with `<feature title>` substituted. It also flips the module's row in `roadmap.md` from `not-started` to `iterating` (without overwriting any user-set Note or any user-chosen non-`not-started` status).

## After scaffold

Tell the user:

> Created `<update-folder-path>`. Module `<module>` is now `iterating` in roadmap. Edit `task_plan.md` to draft phases for this update, then run `/super-manus:impl` to begin work.

Read the new `task_plan.md` and the corresponding `<feature>/prd/<module>.md` so they are in context for the next agent turn.
