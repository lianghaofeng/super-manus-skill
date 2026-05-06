---
description: After a PRD edit, read the prd/<module>.md diff to detect the new milestone intent, then scaffold a fresh update folder with planner-drafted Phases for the user to audit
---

The user has just edited `docs/super-manus/prd/<module>.md` — typically by adding a bullet to `## What users get`, modifying an existing one, or extending `## Quality bar`. They want a new milestone-update folder seeded for that module with a draft Phase list aligned to the change. **`/super-manus:sync` v0.4 reads the PRD git-diff to infer milestone intent** instead of asking the user verbally.

## Setup

This command is v0.4 only. It assumes the project-global v0.4 layout:

```
docs/super-manus/
├── prd/_index.md
├── prd/<module>.md
├── roadmap.md
├── prd_drift.md
└── impl/<module>/<YYYY-MM-DD>-<update>/
```

Verify `docs/super-manus/prd/` is a directory. If absent, tell the user `/super-manus:sync` only works on v0.4 projects (run `/super-manus:start` first); then stop. There is no `.super-manus/active` file in v0.4 — the project root IS the project.

## Resolve the target module

If the user passed a module name as `$ARGUMENTS` (e.g. `/super-manus:sync wiki`), validate it matches `^[a-z0-9][a-z0-9-]*$` and that `docs/super-manus/prd/<module>.md` exists. If not, surface the error and stop.

If `$ARGUMENTS` is empty, list modules from `docs/super-manus/prd/_index.md`'s `## Modules` table (column 1) and ask the user **once**: "Which module is this update for?" — multiple choice. Fall back to `ls docs/super-manus/prd/*.md` (excluding `_index.md`) if the table is missing rows.

## Gather the PRD-diff signal

Run, in order:

1. `git diff HEAD -- docs/super-manus/prd/<module>.md` — captures unstaged + uncommitted edits. This is the most common case (user just edited and saved).
2. If empty, fall back to `git diff HEAD~1..HEAD -- docs/super-manus/prd/<module>.md` — picks up the case where the user already committed the PRD edit before running sync.
3. If both are empty: ask the user **once**: "I see no recent diff for `prd/<module>.md`. State the milestone intent in one sentence." Use that sentence as the milestone signal in lieu of a diff.

**Extract the added bullets** from the diff hunks. Concretely, the lines starting with `+ - ` (or `+- `) under the `## What users get` and `## Quality bar` sections of the diff. These bullets ARE the new capabilities for this milestone — there is no separate intent question to ask.

## Drift check — usually skipped

Because the user just edited PRD to declare the new capability, drift is **impossible by construction**: the intent IS the PRD diff. Skip the Drift check protocol unless one of the following is true in the diff:

- The diff includes **deletions from `## What users get`** (lines starting with `- - ` under that heading) — that is a **Demote / Exclude** scenario for `/super-manus:prd-update`, not a sync. Surface a warning:

  > The diff removes `<deleted bullet>` from `## What users get`. Removing a committed capability is a `/super-manus:prd-update <module>` job (option **Demote** or **Exclude**), not a `/super-manus:sync`. Stopping.

  Then stop. Do not append to `prd_drift.md` (the user's own edit isn't a drift event between PRD and code).

- The diff includes deletions from `## Quality bar` AND adds nothing under `## What users get` or `## Quality bar` — same redirect, same stop.

Otherwise (additions and/or modifications under `## What users get` / `## Quality bar`), the milestone intent is well-defined; continue.

## Pick the update name

Derive a kebab-case slug from the new bullet's first 4–6 meaningful words. Examples:

- `wiki query practice mode` → `wiki-query-practice-mode`
- `expose latency budget on /search` → `expose-latency-budget`

If the bullet contains a `Backed by: <pending: NAME>` marker (the conventional way the user pre-names an upcoming update inside PRD), use `NAME` directly.

Confirm with the user **once**: "Naming this update `<slug>` — OK?" Accept a user-supplied override; the override must match `^[a-z0-9][a-z0-9-]*$`.

## Probe LSP availability

Make one workspace-symbols call (or any cheap LSP probe). Capture the result as `lsp_available = true|false`. This is passed to the planner so it knows whether to lean on LSP for current-state introspection.

## Spawn the sync-planner agent

Spawn the **`sync-planner`** agent (Agent tool, `subagent_type="sync-planner"`). The persona ("senior tech lead"), source-priority hierarchy, and phase-decomposition rules live in [agents/sync-planner.md](../agents/sync-planner.md) — do NOT duplicate them here. The orchestrator only owns the inputs.

Pass these six inputs in the spawning prompt:

- `project_root` — current working directory, absolute path
- `module` — the resolved module name
- `update_name` — the kebab-case slug
- `module_prd_path` — `docs/super-manus/prd/<module>.md` (relative to `project_root`)
- `prd_diff` — the git-diff hunk(s) gathered above (verbatim; the planner will parse added bullets itself)
- `lsp_available` — `true` or `false`

Spawning prompt skeleton:

> Inputs from /super-manus:sync:
>
> - project_root: `<absolute path>`
> - module: `<name>`
> - update_name: `<slug>`
> - module_prd_path: `docs/super-manus/prd/<module>.md`
> - prd_diff: ```<diff hunks>```
> - lsp_available: `<true|false>`
>
> Draft 3–6 candidate Phases for this update per your agent definition. Return the markdown table plus the one-line summary.

The planner returns a markdown table (`| # | Name | Status |` rows with `pending`) and a one-liner summary like "drafted 4 phases, 1 with (audit)".

## Scaffold the update folder

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sm-update.sh" "<module>" "<update-name>"
```

Surface the script's stderr verbatim if it exits non-zero.

The script creates `docs/super-manus/impl/<module>/<YYYY-MM-DD>-<update-name>/` with `task_plan.md`, `findings.md`, `progress.md`, and an empty `tasks/` subfolder, all seeded from templates. It also flips the module's row in `roadmap.md` from `not-started` to `iterating` (without overwriting any user-set Note or any user-chosen non-`not-started` status).

## Inject the planner-drafted Phases into task_plan.md

Read the just-scaffolded `task_plan.md`. Replace the placeholder `## Phases` table — the seeded one row that reads `| 1 | <first phase name> | pending | |` — with the planner's table. Preserve:

- The `## Goal` line (the script populated it with the feature/module/update title; do not overwrite).
- The `<!-- Status values: ... -->` HTML comment after the table.
- The H1 and the file's leading hook-managed comment.

Use the Edit tool with a tight `old_string` (the placeholder row) and `new_string` (the planner's rows). Add a `Notes` column to each planner row with empty content (` |`) so the schema stays `| # | Name | Status | Notes |` per the `task_plan.md` template invariant — the planner returns 3 columns; the orchestrator pads the 4th.

## Tell the user

One short paragraph:

> Created `docs/super-manus/impl/<module>/<YYYY-MM-DD>-<update-name>/`. Module `<module>` is now `iterating` in roadmap. Drafted **\<N\>** candidate phases (`<M>` marked `(audit)`) from the PRD diff. **Audit `task_plan.md` ## Phases before running `/super-manus:impl`.**

Read the new `task_plan.md` and the corresponding `docs/super-manus/prd/<module>.md` so they are in context for the next agent turn.

## Do NOT auto-run /super-manus:impl

The user must audit the phase list first. `(audit)` markers exist precisely because the planner is unsure; the user removes them or rewrites the row. Auto-running `/super-manus:impl` would skip that audit loop and is forbidden in v0.4.
