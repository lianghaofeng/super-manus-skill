---
description: Global super-manus switch — read full project state, decide the next action, run a drift scan, and execute
---

The user said "you decide" — they don't know which super-manus command applies right now. Your job is to read the whole picture and pick exactly one next action, announce it as a decision + reason in one line, then execute it.

## Read everything

Confirm `docs/super-manus/prd/` is a directory. If absent, super-manus is not enabled — tell the user and offer `/super-manus:start` to enable it (or `/super-manus:reverse-prd-spec` after that, if there's an existing codebase to bootstrap from — renamed from `/super-manus:reverse-prd` in v0.9.5 R9).

Read in this order:

1. `docs/super-manus/prd/_index.md`
2. `docs/super-manus/roadmap.md`
3. `docs/super-manus/drift_log.md` (v0.9.5 R10 — read both H2 sections: `## PRD drift` and `## Spec drift`)
4. For each module listed in `_index.md`: scan `docs/super-manus/impl/<module>/` for the most recently modified update folder, then read its `task_plan.md` Phases table. Use `sm_active_update` (sourced from `${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh`, no arguments) to identify the most-recent update across all modules.

## Decide the next action

Pick the FIRST applicable rule:

| State | Decision |
|---|---|
| `prd/_index.md` is still the seeded placeholder (Problem / Demo / Must / Modules empty) | Run `/super-manus:brainstorm` |
| `drift_log.md ## PRD drift` has rows with `Resolution = pending` | Run `/super-manus:prd-update <module-from-pending-row>` (pick the oldest pending) |
| `drift_log.md ## Spec drift` has rows with `Resolution = pending` | Run `/super-manus:spec-update <module-from-pending-row>` (pick the oldest pending) |
| `roadmap.md` has any module with Status `not-started` AND no module is currently `iterating` | Run `/super-manus:sync <not-started-module>` |
| Any module is `iterating` AND its latest update has phases in `pending` or `in_progress` | Run `/super-manus:impl` (resume the active update) |
| All modules are `stable` or `blocked` and no other state listed | Tell the user the project is done (or stuck on blocked); offer `/super-manus:sync <module>` for a new milestone |

If two rules tie, prefer earlier rows in this table — drift takes priority over progress.

## Announce decision

In ONE line, before any tool call: "Decision: `<chosen-command>`. Reason: `<one-sentence why>`."

Example: "Decision: `/super-manus:impl`. Reason: api module is iterating, phase 2 of the active update is in_progress."

## Execute

Auto mode is the common case here — proceed to execute the chosen command's body directly. Follow that command's `commands/*.md` instructions. Do NOT invoke another `Skill` or slash command nesting; just inline the work.

## Drift scan (always)

Before running the chosen action's body, do a quick PRD ↔ implementation drift scan across all modules:

For each module M with at least one update folder:

1. Read `docs/super-manus/prd/M.md ## What users get` and `## Out of scope`.
2. Read the most recent update's `progress.md ## Completed commits`.
3. If a commit message hints at a capability not in `## What users get` or contradicts `## Out of scope`, append one row to `docs/super-manus/drift_log.md ## PRD drift` (v0.9.5 R10 — drift_log replaces the old prd_drift.md; PRD-side drift goes under the `## PRD drift` H2):
   ```
   | <YYYY-MM-DD> | <author> | M | <one-line>: <commit hint> not declared in prd/M.md | pending |
   ```
   The `<author>` cell is sourced from `git config user.name` (fall back to `unknown` if unset) — v0.9.7 R15 schema: `Date | Author | Module | Conflict | Resolution`.
4. Do NOT silently update the PRD. The drift row is a flag; resolution waits for the user via `/super-manus:prd-update`.

Surface a one-line summary of new drift rows (if any) before executing the chosen action. If new drift was logged AND it conflicts with the chosen action, override and run `/super-manus:prd-update <module>` instead.

## Final report

Whatever you executed, report in ONE line at the end: "Done — `<command>` executed; `<one-line outcome>`. Next: `<one suggestion>`."
