---
description: PRD-led 5-question brainstorm — write prd/_index.md and per-module prd/<module>.md stubs, then seed the first MVP update folder
---

The user wants to brainstorm a v0.2 feature into a PRD folder + a first MVP update milestone.

## Setup

Resolve the active feature folder by reading `.super-manus/active`. The folder is `docs/super-manus/<that-name>/`. If `.super-manus/active` is missing or empty, tell the user there is no active feature and suggest `/super-manus:start <name>` first; then stop.

Confirm `<feature>/prd/` is a directory (v0.2 layout). If `<feature>/prd.md` exists as a file (legacy v0.1), tell the user `/super-manus:brainstorm` only operates on v0.2 features and stop.

Read the existing `<feature>/prd/_index.md` and any existing `<feature>/prd/*.md`. If `prd/_index.md` already has substantive content (any of `## Problem`, `## Demo`, `## Must` is non-empty / non-placeholder, OR the `## Modules` table has rows), ask once: "PRD already exists. Refine in place (default) or replace from scratch?" Then proceed accordingly. Refine-in-place means: keep what's there, surgically extend or correct.

## The 5 questions (one per turn, in order)

Ask ONE question at a time. Wait for the user's answer before the next. Maximum 5 questions total. Skip a question only if the user already answered it implicitly.

1. **Problem** — "In one sentence: what pain are we relieving, and for whom?"
2. **Users / trigger** — "Who's the primary user, and what moment triggers them to reach for this?" (a moment, not a job title)
3. **Demo** — "Walk me through 3–5 lines of how someone uses this, second-person concrete. If unsure I can offer A) ... and B) ... — just pick one." Offer 2 alternatives only if the user is uncertain; otherwise just take their description.
4. **Must vs Not doing** — "List the must-have capabilities (3–7 short lines), then anything you want to explicitly NOT do that someone might assume is in scope."
5. **Modules** — "What system modules should this split into? Suggest 1–3 candidates yourself based on the Must list (e.g. `db / api / frontend / cli`); user confirms or edits. Each module name must be lowercase kebab-case (matching `^[a-z0-9][a-z0-9-]*$`)."

After the 5 (or fewer if the user converged early), optionally probe ONCE for cross-module data flow: "How do these modules connect? One paragraph." If the user can't articulate it, leave it blank.

## Hard constraints

- **Do NOT** ask about database schemas, API endpoints, libraries, frameworks, performance budgets, or implementation architecture. Those belong in per-module `prd/<module>.md ## Surface` (which the user fills after this command, or refines via `/super-manus:prd-update`) and the active update's `tasks/p<n>_impl.md ## Approach` per phase.
- **Do not propose architecture** in your follow-ups. Stay in product semantics.
- Keep the final `prd/_index.md` under **700 words** total.
- Keep each per-module `prd/<module>.md` stub under **2000 words** total. The stub can be terse — the user will flesh it out later.
- One question per turn. Don't bundle.

## Writing the PRD folder

When you have answers (or 5 turns elapsed), write the following files. Use the `prd_index.md` and `prd_module.md` templates as starting structure (their headings are stable: `## Problem` / `## Demo` / `## Must` / `## Not doing` / `## Modules` / `## Data flow overview` for `_index.md`; `## Purpose` / `## Surface` / `## Data flow` / `## Constraints` / `## Out of scope` / `## Open questions` for each module file).

1. **`<feature>/prd/_index.md`** — replace the seeded placeholder with the user's answers. Fill the `## Modules` table with one row per module, columns `| Module | File | Purpose |`, with `File` as a relative link `[prd/<module>.md](<module>.md)` and `Purpose` as a one-line summary.

2. **`<feature>/prd/<module>.md`** for each module — copy from `templates/prd_module.md`, substitute `<module name>` with the actual module name, and pre-fill `## Purpose` from the user's module split. Leave `## Surface`, `## Data flow`, `## Constraints`, `## Out of scope`, `## Open questions` as light placeholders for the user (or `/super-manus:prd-update`) to flesh out — the brainstorm command must NOT invent schema/API content here.

3. **`<feature>/roadmap.md`** — under `## Modules`, add one row per module: `| <module> | not-started | |`. Drop the `<module-a>` placeholder if it's still there (it shouldn't be after commit 1 templates, but be defensive).

Use the user's answers verbatim where possible. Keep each section terse — Problem and Demo are 1–3 sentences; Must / Not doing are bullet lists.

## After the PRD lands — seed the first MVP update

Pick the FIRST module in the user's module list. Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sm-update.sh" "<first-module>" "mvp"
```

This creates `<feature>/impl/<first-module>/<YYYY-MM-DD>-mvp/` with `task_plan.md`, `findings.md`, `progress.md`, and an empty `tasks/`, all seeded from templates. It also flips `<first-module>`'s row in `roadmap.md` from `not-started` to `iterating`.

Surface the script's stderr verbatim if it exits non-zero.

Tell the user:

> PRD seeded: `prd/_index.md` + `<N>` per-module files. First MVP update at `<update-folder-path>` (module `<first-module>` is now `iterating`).
>
> Next steps:
> 1. Edit `prd/<module>.md ## Surface` to flesh out the target state (you can do this any time).
> 2. Edit `<update-folder-path>/task_plan.md` to draft phases for the MVP.
> 3. Run `/super-manus:impl` to begin work, or `/super-manus:sync <other-module>` to start a different module.

Read `prd/_index.md` and the new update's `task_plan.md` so they are in context for the next agent turn. Do not propose architecture or write any `tasks/p<n>_impl.md` — that's `/super-manus:impl`'s job.
