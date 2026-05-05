# super-manus — Design Doc (v0.2)

> **This is the current design. v0.1 (`design.md`) is superseded.**
> Validated through brainstorming session 2026-05-06.
> Status: design locked, ready to enter writing-plans.

## 1. What changed from v0.1

v0.1 treated PRD as a single ≤500-word product-only file (`prd.md`), with a strict three-layer separation: PRD (WHAT) → task_plan (HOW-overview) → phase impl (HOW-detail).

In real use this didn't scale. Mid-size features have multiple system modules (db / api / frontend / infra / ...), each with its own product surface. A single PRD file either becomes too thin to drive implementation or bloats past 500 words. And there was no mechanism to detect or repair PRD ↔ implementation drift — PRD silently went stale.

**v0.2 reshapes the model around two axes: module (space) × milestone (time).**

- PRD becomes a **folder** (`prd/`), one file per module, each ≤2000 words, allowed to include schema / interface / UX outline (the "Surface" — module's target state).
- Implementation work happens in **per-module per-milestone update folders** under `impl/<module>/<YYYY-MM-DD>-<update-name>/`, each containing the existing v0.1 four-file set (task_plan / findings / progress / tasks/p<n>_impl).
- A new **drift log** (`prd_drift.md`) records every PRD ↔ implementation conflict.
- A new **roadmap** (`roadmap.md`) tracks per-module status across the feature.
- Drift detection is enforced by the agent on every `impl` and at phase close — PRD is no longer silent state, it is actively reconciled with reality.
- Command set collapses to **7** (down from 6 in v0.1, by absorbing `phase` / `catchup` / `log` into a smarter `impl` and a new global `drive` switch).

## 2. Core principles

1. **PRD is module target state.** It is revised only via `/super-manus:prd-update <module>` (minimum surgical edit, no changelog markers). PRD reads like a product snapshot, not a changelog.
2. **impl is module timeline.** Each milestone update is a folder with a date prefix; old updates are immutable historical records, the latest is the active one.
3. **PRD ↔ implementation alignment is enforced.** When implementation diverges from PRD, the agent stops, logs to `prd_drift.md`, and asks the user: revert implementation, or update PRD?
4. **Reuse v0.1 internals verbatim.** The four-file set inside each update folder uses the existing schema names (task_plan.md / findings.md / progress.md / tasks/p<n>_impl.md). No internal-file rename, no template-heading rename. Hooks and scripts only see a path-prefix change.

## 3. Scope (v0.2)

**In:**

- Per-feature folder, with new structure (see §4)
- PRD folder model with `_index.md` manifest + per-module files
- Per-module per-milestone update folders, reusing v0.1 four-file set internally
- `roadmap.md` (auto-managed module status table)
- `prd_drift.md` (drift log)
- Drift detection at impl-time and phase-close-time
- 7 slash commands (see §6)
- Hooks adjusted to write into the active update folder (not feature root)
- `using-sm` skill rewritten to teach the two-axis model
- New design doc supersedes v0.1's; v0.1 plan kept as historical record

**Out (deferred to v0.3+):**

- Migration of v0.1 features to v0.2 layout — v0.2 only applies to **new** features. Old features keep working under v0.1 rules; hooks branch on `prd/` being a folder vs a file.
- Per-module test folders (rejected as over-design — test design intent goes in `prd/<module>.md ## Constraints` or in `impl/<module>/<update>/findings.md`)
- Module rename command (low frequency, manual operation)
- TDD task executor / subagent dispatch / code review / multi-harness (still v0.1 deferred items)

## 4. File layout (project-side)

```
<project-root>/
├── .super-manus/
│   └── active                                  # feature folder name (unchanged)
└── docs/super-manus/
    └── <YYYY-MM-DD>-<feature-name>/
        ├── prd/
        │   ├── _index.md                       # feature overview + module manifest + data flow overview (≤700 words)
        │   └── <module>.md × N                 # per-module PRD, target state, ≤2000 words
        ├── impl/
        │   └── <module>/
        │       └── <YYYY-MM-DD>-<update-name>/
        │           ├── task_plan.md            # v0.1 schema, unchanged
        │           ├── findings.md             # v0.1 schema, unchanged
        │           ├── progress.md             # v0.1 schema, unchanged (hook-managed)
        │           └── tasks/
        │               └── p<n>_impl.md        # v0.1 schema, unchanged
        ├── roadmap.md                          # module status table
        └── prd_drift.md                        # drift log
```

**Active-update resolution.** No second active-state file. The agent and hooks resolve "current active update for module X" by scanning `impl/<module>/` for the most recently modified subfolder. This keeps state implicit and avoids stale pointers.

## 5. File contracts

### `prd/_index.md`

```markdown
# <feature title>

## Problem
<one sentence>

## Demo
<3–5 lines, second person, concrete>

## Must
- <one-liner each>

## Not doing
- <explicit non-goals>

## Modules
| Module | File | Purpose |
| --- | --- | --- |
| <module-a> | [prd/<module-a>.md](prd/<module-a>.md) | <one line> |

## Data flow overview
<text or simple diagram describing how modules connect>
```

Total ≤700 words. Module manifest is the source of truth for which modules exist.

### `prd/<module>.md`

```markdown
# <module name>

## Purpose
<one sentence: this module's job>

## Surface
<schema / interface / UX outline — target state. Tables, fields, endpoint paths, screens are OK. No code snippets, no file paths.>

## Data flow
<who calls in, where outputs go>

## Constraints
<perf, compat, security non-negotiables>

## Out of scope
<what this module won't do>

## Open questions
<unresolved product questions; remove after answered>
```

Total ≤2000 words. **No changelog markers** in any section: no strikethrough, no "(was: ...)", no dated revision marks. PRD is current-state; history lives in git log + `findings.md`.

### `roadmap.md`

```markdown
# Roadmap

## Modules
| Module | Status | Note |
| --- | --- | --- |
| <module-a> | iterating | <one line, optional> |
| <module-b> | not-started | |
| <module-c> | stable | |
```

Status values: `not-started` / `iterating` / `stable` / `blocked`. Auto-managed by `start`, `sync`, `prd-add-module`, and `impl` (which flips `not-started` → `iterating` on first use, and `iterating` → `stable` when a phase closes the milestone). User may add a one-line note in the Note column; agent should not overwrite it.

### `prd_drift.md`

```markdown
# PRD drift log

| When | Module | Conflict | Resolution |
| --- | --- | --- | --- |
| 2026-05-06 | api | impl introduced /tags endpoint, not in PRD ## Surface | prd-update: added |
```

Append-only. One row per drift event. Resolution column filled in after the user decides (revert / prd-update).

### `impl/<module>/<YYYY-MM-DD>-<update-name>/*` (the four-file set)

**Use v0.1 schema verbatim.** task_plan.md / findings.md / progress.md / tasks/p<n>_impl.md keep their existing headings, formats, and rules. The only thing different is the path prefix.

## 6. Command set (MVP, 7 commands)

| Command | Trigger | Purpose |
|---|---|---|
| `/super-manus:drive` | user | Global switch — agent reads everything (PRD, roadmap, drift log, all impl updates) and decides the next action; runs drift scan |
| `/super-manus:start <feature>` | user | Create feature folder with v0.2 layout (`prd/` folder, `impl/`, `roadmap.md`, `prd_drift.md`) |
| `/super-manus:brainstorm` | user | 5 questions, last question is module split → write `prd/_index.md` + per-module PRD stubs → auto-create the first MVP update folder with the four-file set |
| `/super-manus:reverse-prd` | user | Scan an existing project, infer module breakdown, generate `prd/` folder; one-shot, user audits afterward |
| `/super-manus:sync <module>` | user | After PRD edits, create a new update folder under `impl/<module>/`, seeded against the latest PRD module file |
| `/super-manus:prd-update <module>` | user | Single-module PRD surgical edit (5 options: tighten / split / demote / exclude / add); writes a paired `findings.md ## Decisions` entry in the active update |
| `/super-manus:impl [target]` | user | Resume work in an update folder. `target` may be: omitted (use most recent active update across all modules), a module name (use that module's latest update), or an update folder name. Auto-selects next pending phase, generates `tasks/p<n>_impl.md` draft, continues execution. Replaces v0.1's `phase` and `catchup`. |

**Removed from v0.1:** `phase` (absorbed into `impl`), `catchup` (absorbed into `impl` and `drive`), `log` (auto-fired by hooks; manual force-write deferred to v0.3 if anyone misses it).

## 7. Drift detection rules

The agent must run a PRD ↔ implementation alignment check at three points:

1. **At the start of `/super-manus:impl`** — read the active update's `task_plan.md` next pending phase + corresponding `prd/<module>.md`. If the phase intent introduces a capability not declared in `## Surface` / `## Constraints`, write a `prd_drift.md` row and pause: tell the user "drift detected: revert phase or `/super-manus:prd-update <module>`". Do not proceed silently.
2. **At phase close (when a `task_plan.md` row flips to `closed`)** — re-read `prd/<module>.md` and the update's `progress.md ## Completed commits`. Report two diffs: "PRD declared but not implemented" and "implemented but not in PRD". Drift rows logged for the second.
3. **Inside `/super-manus:drive`** — full feature drift scan as part of the global health check.

Drift is **always logged**; resolution is **always user-decided**. The agent does not silently update PRD.

## 8. Hook adjustments

Existing hooks change minimally — only the path they write to.

- **`hooks/post-commit.sh`**: instead of `<feature>/progress.md`, write to `<feature>/impl/<module>/<latest-update>/progress.md`. The "current module" is inferred by reading `task_plan.md` of the most-recently-modified update folder across all modules. If ambiguous, fall back to writing nothing and emitting a one-line warning in the agent context.
- **`hooks/session-end.sh`**: same path adjustment.
- **`hooks/session-start.sh`**: emit a "v0.2 active feature" banner suggesting `/super-manus:drive` if uncertain, instead of dumping `task_plan.md` directly (there is no longer a single canonical task_plan).
- **`hooks/lib.sh`**: new helper `sm_active_update <feature>` returning `<module>/<update-folder-name>` of the most recently modified update across all modules.

Backward compatibility: hooks first probe whether `<feature>/prd/` is a directory. If yes → v0.2 mode. If `<feature>/prd.md` is a file → v0.1 mode (unchanged behavior).

## 9. Skill rewrite (`skills/using-sm/SKILL.md`)

Sections to rewrite:

- §1 file layout — replace tree
- §2 what goes in which file — replace PRD section, keep findings/task_plan/progress/p_impl sections (they apply per-update now), add roadmap and prd_drift sections
- §3 update triggers — add drift-detection rules
- New §7 "Two-axis model" — explains module × milestone organization

Anti-pattern list extended:

- "Don't put changelog markers in PRD modules"
- "Don't write to `prd_drift.md` by hand — only via drift detection or prd-update follow-up"
- "Don't overwrite the user's Note column in `roadmap.md`"

## 10. Implementation breakdown (5 commits)

Order is risk-ascending, per `CLAUDE.md` "small commits, one logical change per commit" and the "tests must run green" gate.

1. **Templates + template tests** — add `templates/prd_index.md`, `templates/prd_module.md`, `templates/roadmap.md`, `templates/prd_drift.md`, and matching `tests/test_template_*.sh`. No logic changes. Pure additive.
2. **`start` upgrade + `lib.sh` helper** — `/super-manus:start` creates the v0.2 layout for new features. `sm_active_update()` added. Hooks unchanged (still v0.1 paths) — they probe and fall back to v0.1 mode because no `impl/` updates exist yet.
3. **`brainstorm` upgrade + new `prd-update` and `sync` commands** — PRD maintenance loop is complete. After this commit, a user can hand-author features end-to-end at the PRD layer.
4. **New `impl` and `drive` commands + hook path adjustments** — execution layer. Hooks now write into the active update folder. This is the highest-risk commit; tests for hooks are mandatory.
5. **`reverse-prd` + `using-sm/SKILL.md` rewrite + `design.md` v0.1 banner + `README.md` update** — closing documentation and the reverse-engineering helper.

Each commit must pass `bash tests/run-all.sh`.

## 11. Tests added

- `tests/test_template_prd_index.sh`
- `tests/test_template_prd_module.sh`
- `tests/test_template_roadmap.sh`
- `tests/test_template_prd_drift.sh`
- `tests/test_command_drive_logic.sh`
- `tests/test_command_sync_logic.sh`
- `tests/test_command_prd_update_logic.sh`
- `tests/test_command_reverse_prd_logic.sh`
- `tests/test_command_impl_logic.sh`
- Existing tests parametrized to accept both v0.1 (single `prd.md`) and v0.2 (`prd/` folder) layouts where they overlap.

## 12. Out-of-scope clarifications (v0.2)

To prevent scope creep:

- **No tests folder per module.** Test design intent goes in `prd/<module>.md ## Constraints`; per-day test outcomes go in the update's `findings.md ## Data points`.
- **No PRD revision history file.** History is reconstructed from `git log` + `findings.md ## Decisions` (which gets a paired entry on every `prd-update`). This is the "no changelog markers" rule's logical complement.
- **No phase concept above the module level.** `task_plan.md` exists only inside an update folder, scoped to that one update. Across-feature progress comes from `roadmap.md`.
- **No automatic `roadmap.md` Note column edits.** Only the user writes there.
- **No multi-update simultaneous active per module.** A module has at most one in-progress update at a time; opening a new one auto-closes the previous (its task_plan should be all `closed` or it is left as `blocked`).
- **No migration of v0.1 features.** Both layouts coexist via hook-side probing. A migration command may come in v0.3 if there is demand.

## 13. Open questions (resolve before commit 4)

- The "module" inference for hook writes when multiple updates were modified within seconds of each other — current plan is "most recent mtime wins", but a tie-break may need git-aware logic (e.g. which update folder has files staged in the current commit). Validate with a tests/test_hook_post_commit fixture covering the ambiguous case.
- `/super-manus:drive`'s drift scan cost — if a feature has 10 modules × 5 updates each, scanning every PRD vs every progress.md is expensive. Likely fine for v0.2 (typical features have 3-5 modules), but worth measuring on the dogfood feature.
