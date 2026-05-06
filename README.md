# super-manus

*Survives `/clear`, generates dev-readable progress journals from git history, works alongside superpowers (not a fork).*

## What

**super-manus** is a Claude Code plugin that fuses [obra/superpowers](https://github.com/obra/superpowers)' execution discipline with Manus-style ([OthmanAdi/planning-with-files](https://github.com/OthmanAdi/planning-with-files)) persistent file-based state. It owns the state layer only: a per-feature folder on disk holds your PRD, plan, findings, and progress journal, and hooks keep them in sync as you work.

## Why

`superpowers` gives you TDD, subagent dispatch, and code-review discipline, but loses everything on `/clear` or `/compact`. `planning-with-files` gives you Manus-style persistent state across sessions, but no execution discipline.

super-manus targets the gap: persistent state that survives session boundaries, with hooks that auto-restore "where were we" without user babysitting. It does NOT re-implement superpowers' executor — super-manus owns the **state layer**. Keep using superpowers (or any other workflow) for execution.

## v0.2 — two-axis model

v0.2 reshapes the model around **module (space) × milestone (time)**:

- **PRD is a folder** (`prd/`), one file per module (db / api / frontend / ...). Each per-module PRD allows schema sketches, interface outlines, UX flows in its `## What users get` section — the level of detail a PM gives engineering — capped at ~2000 words. Under that, nine stable headings (Why this exists / Users / Success / What users get / How it connects / Quality bar / Risks / Out of scope / Open questions). The feature-level `prd/_index.md` adds Audience + Success metrics on top of the v0.1 Problem / Demo / Must / Not doing / Modules / Data flow overview.
- **Implementation is per-module per-milestone**: each "milestone update" is a folder under `impl/<module>/<YYYY-MM-DD>-<update-name>/` containing the v0.1 four-file set (`task_plan.md`, `findings.md`, `progress.md`, `tasks/p<n>_impl.md`). Old updates are immutable historical record; the latest is active.
- **PRD ↔ implementation alignment is enforced**: when intent diverges from PRD, the agent stops, logs to `prd_drift.md`, and asks the user — revert implementation, or run `/super-manus:prd-update <module>`. PRD is never silently updated.

v0.1 features keep working through hook fallbacks; v0.2 only applies to features started with the v0.2 `/super-manus:start`. See [docs/design-v0.2.md](docs/design-v0.2.md) for the full design.

## Install

**Recommended — add the marketplace, then `/plugin` install:**

```
/plugin marketplace add https://github.com/lianghaofeng/super-manus-skill
/plugin install super-manus@super-manus-skill
```

You'll get future updates via `/plugin marketplace update super-manus-skill`.

**Local marketplace (for local development or if remote install fails):**

```
/plugin marketplace add /path/to/super-manus
/plugin install super-manus@super-manus-skill
```

Point at a local clone of this repo — `marketplace.json` lives at `.claude-plugin/marketplace.json` and resolves the plugin from the same checkout.

On first install, restart your Claude Code session so hooks and slash commands register.

## Quickstart (v0.2)

```
/super-manus:start my-feature             # creates docs/super-manus/<date>-my-feature/
                                          # with prd/_index.md, empty prd/, empty impl/,
                                          # roadmap.md, prd_drift.md
/super-manus:brainstorm                   # 6 questions (last = module split). Writes prd/_index.md
                                          # + per-module prd/<module>.md stubs, then auto-seeds
                                          # impl/<first-module>/<date>-mvp/ with the four-file set
... user audits prd/<module>.md files, fleshes out ## What users get ...
/super-manus:impl                         # auto-finds next pending phase in the active update,
                                          # seeds tasks/p<n>_impl.md, drift-checks against PRD,
                                          # proceeds to draft + execute
git commit -m "..."                       # post-commit hook prompts agent to log into the active
                                          # update's progress.md
/clear                                    # safe — state is on disk
... next session ...                      # SessionStart hook injects the active update's task_plan
```

When PRD and implementation diverge:

```
/super-manus:prd-update <module>          # surgical edit on a single per-module PRD (5 options:
                                          # tighten / split / demote / exclude / add). No changelog
                                          # markers; paired entry in active update's findings.md.
/super-manus:sync <module>                # PRD changed — scaffold a new update folder for that module
```

When you don't know what to do next, use the global switch:

```
/super-manus:drive                        # reads everything, picks one of brainstorm / sync /
                                          # prd-update / impl, announces decision + reason, executes
```

For an existing project that has no PRD yet:

```
/super-manus:reverse-prd                  # one-shot: scan source, infer modules, generate
                                          # prd/_index.md + per-module stubs (audit afterwards)
```

**Two-axis model** (no overlap):

- `prd/<module>.md` is **WHAT** the module IS (target state). `## What users get` carries schema sketches / endpoint outlines / screen flows; `## Quality bar` carries user-visible NFRs.
- `impl/<module>/<update>/task_plan.md` is **HOW-overview** for ONE milestone of work on that module.
- `impl/<module>/<update>/tasks/p<n>_impl.md` is **HOW-detail** — DB migrations, API code, file diffs per phase.

PRD updates only via `/super-manus:prd-update <module>` (single-section, ≤2000 words, no changelog markers). Drift between PRD and implementation is logged to `prd_drift.md` and resolved by the user.

**Session log cadence** is unchanged from v0.1 — Stop hook rate-limits checkpoints via `SUPER_MANUS_LOG_EVERY_N_TURNS` (default 5) and `SUPER_MANUS_LOG_MODE` (`both` / `turns` / `commit` / `off`); the agent judges whether to write each time. In v0.2 the state file moves into the active update folder, so per-update turn counts are isolated.

## Layout

The on-disk layout super-manus creates inside a project that uses it (v0.2):

```
<project-root>/
├── .super-manus/
│   └── active                                  # text file: current feature folder name
└── docs/super-manus/
    └── <YYYY-MM-DD>-<feature-name>/
        ├── prd/
        │   ├── _index.md                       # feature overview + module manifest + data flow (≤700 words)
        │   └── <module>.md                     # per-module target state (≤2000 words; /super-manus:prd-update)
        ├── impl/
        │   └── <module>/
        │       └── <YYYY-MM-DD>-<update-name>/
        │           ├── task_plan.md            # phase index for this update
        │           ├── findings.md             # decisions / errors / data points for this update
        │           ├── progress.md             # commits + session log for this update (hook-managed)
        │           └── tasks/
        │               └── p<n>_impl.md        # per-phase technical plan (lazy, /super-manus:impl)
        ├── roadmap.md                          # module status table (auto-managed)
        └── prd_drift.md                        # PRD ↔ implementation conflict log (append-only)
```

v0.1 features keep their flat layout (`<feature>/{prd.md,task_plan.md,findings.md,progress.md,tasks/}`); both shapes coexist via hook-side probing.

## What it does NOT do

v0.2 stays small. Out of scope:

- Migration of v0.1 features to v0.2 layout (both layouts coexist; no migration command planned)
- Per-module test folders (test design intent goes in `prd/<module>.md ## Quality bar`; per-day test outcomes go in the update's `findings.md`)
- Module rename command (low frequency — rename folders + edit `prd/_index.md` manually)
- TDD task executor / subagent dispatch / code review / multi-harness — still v0.1's deferred items
- Automated test running (use your existing toolchain)
- PR creation or merge integration

## Coexistence with superpowers

super-manus and superpowers can both be installed; they don't fight:

- super-manus owns SessionStart / Stop / PostToolUse hooks for the **state layer**.
- superpowers owns its own SessionStart hook for skill bootstrap — both fire, both inject, no conflict.
- super-manus skills don't auto-trigger; `using-sm` is invoked only when you run `/super-manus:*`.
- Plans written by superpowers' `writing-plans` (`docs/plans/*.md`) are independent of super-manus' feature folders.

## Status

v0.2 — module × milestone two-axis model with PRD-folder + drift detection. v0.1 (single `prd.md` flat folder) remains supported via hook fallbacks. See [docs/design-v0.2.md](docs/design-v0.2.md) for the full design and [docs/design-v0.1.md](docs/design-v0.1.md) for the historical v0.1 spec.
