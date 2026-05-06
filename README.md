# super-manus

*Survives `/clear`, generates dev-readable progress journals from git history, works alongside superpowers (not a fork).*

## What

**super-manus** is a Claude Code plugin that fuses [obra/superpowers](https://github.com/obra/superpowers)' execution discipline with Manus-style ([OthmanAdi/planning-with-files](https://github.com/OthmanAdi/planning-with-files)) persistent file-based state. It owns the state layer only: a project-global folder on disk holds your PRD, plan, findings, and progress journal, and hooks keep them in sync as you work.

## Why

`superpowers` gives you TDD, subagent dispatch, and code-review discipline, but loses everything on `/clear` or `/compact`. `planning-with-files` gives you Manus-style persistent state across sessions, but no execution discipline.

super-manus targets the gap: persistent state that survives session boundaries, with hooks that auto-restore "where were we" without user babysitting. It does NOT re-implement superpowers' executor — super-manus owns the **state layer**. Keep using superpowers (or any other workflow) for execution.

## v0.4 — project-global PRD

v0.4 hoists PRD / roadmap / prd_drift to project-global level and removes the per-feature timestamped wrapper folder. The v0.3 layout wrapped everything in `docs/super-manus/<YYYY-MM-DD>-<feature>/`, which conflated two concepts: the PRD (a current-state snapshot of the whole project) and the impl time-series (per-update milestones). v0.4 separates them:

- **PRD is project-global** (`docs/super-manus/prd/`), one file per module (db / api / frontend / ...). Each per-module PRD allows schema sketches, interface outlines, UX flows in its `## What users get` section — the level of detail a PM gives engineering — capped at ~2000 words. Under that, nine stable headings (Why this exists / Users / Success / What users get / How it connects / Quality bar / Risks / Out of scope / Open questions). The project-level `prd/_index.md` adds Audience + Success metrics on top of Problem / Demo / Must / Not doing / Modules / Data flow overview.
- **Implementation is per-module per-milestone**: each "milestone update" is a folder under `docs/super-manus/impl/<module>/<YYYY-MM-DD>-<update-name>/` containing the four-file set (`task_plan.md`, `findings.md`, `progress.md`, `tasks/p<n>_impl.md`). Old updates are immutable historical record; the latest is active. Timestamps appear ONLY here.
- **PRD ↔ implementation alignment is enforced**: when intent diverges from PRD, the agent stops, logs to `prd_drift.md`, and asks the user — revert implementation, or run `/super-manus:prd-update <module>`. PRD is never silently updated.
- **No active-state file.** The `.super-manus/active` pointer from v0.2/v0.3 is gone. Hooks resolve the active update purely by mtime scan of `docs/super-manus/impl/<module>/*/`. The "feature" abstraction is gone — there is one project = one PRD.

See [docs/design-v0.4.md](docs/design-v0.4.md) for the full design. v0.2/v0.3 design is preserved at [docs/design-v0.2.md](docs/design-v0.2.md) (superseded).

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

## Quickstart (v0.4)

```
/super-manus:start                        # idempotently seeds docs/super-manus/{prd,impl}/,
                                          # roadmap.md, prd_drift.md (no arguments)
/super-manus:brainstorm                   # 6 questions (last = module split). Writes
                                          # docs/super-manus/prd/_index.md + per-module
                                          # prd/<module>.md stubs at not-started in roadmap
... user audits prd/<module>.md files, fleshes out ## What users get ...
/super-manus:sync <module>                # reads `git diff prd/<module>.md` to detect the new
                                          # capability you just added, spawns the sync-planner
                                          # agent to draft 3-6 candidate Phases (with (audit)
                                          # markers), scaffolds docs/super-manus/impl/<module>/
                                          # <date>-<name>/ with the four-file set + planner's
                                          # Phases; flips module to iterating
... user reviews task_plan.md Phases (planner-drafted, not blank) ...
/super-manus:impl                         # auto-finds next pending phase, runs drift check,
                                          # spawns the impl-architect agent to draft tasks/
                                          # p<n>_impl.md, then proceeds to write code +
                                          # commit. End-of-update: BLOCKING drift gate refuses
                                          # to mark the update done while prd_drift.md has
                                          # pending rows for the module.
git commit -m "..."                       # post-commit hook prompts agent to log into the active
                                          # update's progress.md
/clear                                    # safe — state is on disk
... next session ...                      # SessionStart hook injects prd/_index.md + the active
                                          # update's task_plan
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
/super-manus:reverse-prd                  # one-shot: orchestrator does runtime-first module
                                          # discovery (compose / Makefile / apps / scripts),
                                          # then spawns the reverse-prd-architect agent (chief
                                          # architect + senior PM persona) which writes
                                          # docs/super-manus/prd/_index.md (with a mandatory
                                          # ASCII architecture diagram) + per-module stubs.
                                          # Audit (audit) markers afterwards, then sync per module.
```

**Two-axis model** (no overlap):

- `prd/<module>.md` is **WHAT** the module IS (target state). `## What users get` carries schema sketches / endpoint outlines / screen flows; `## Quality bar` carries user-visible NFRs.
- `impl/<module>/<update>/task_plan.md` is **HOW-overview** for ONE milestone of work on that module.
- `impl/<module>/<update>/tasks/p<n>_impl.md` is **HOW-detail** — DB migrations, API code, file diffs per phase.

PRD edits in v0.4 follow two paths:

- **Normal iteration**: edit `prd/<module>.md` directly (add a `## What users get` bullet, tighten `## Quality bar`), then run `/super-manus:sync <module>` — sync v2 reads the git diff and drafts Phases for the new capability automatically.
- **Surgical drift absorption**: when implementation has already deviated and you want PRD to move (rather than reverting code), use `/super-manus:prd-update <module>` for a single-section minimum edit (5 options: tighten / split / demote / exclude / add). The active update's `findings.md` gets a paired Decision entry; `prd_drift.md` row's Resolution flips out of `pending`, unblocking the end-of-update drift gate.

Drift between PRD and implementation is always logged to `prd_drift.md` (append-only) and resolved by the user. PRD files cap at ≤2000 words per module / ≤700 words for `_index.md`. No changelog markers anywhere — PRD is a current-state snapshot, history lives in `git log` and `findings.md`.

**Session log cadence** is unchanged — the Stop hook rate-limits checkpoints via `SUPER_MANUS_LOG_EVERY_N_TURNS` (default 5) and `SUPER_MANUS_LOG_MODE` (`both` / `turns` / `commit` / `off`); the agent judges whether to write each time. The state file lives inside the active update folder, so per-update turn counts are isolated.

## Layout

The on-disk layout super-manus creates inside a project that uses it (v0.4):

```
<project-root>/
└── docs/super-manus/
    ├── prd/                                    # project-global, ONE source of truth
    │   ├── _index.md                           # project overview + module manifest + data flow (≤700 words)
    │   └── <module>.md                         # per-module target state (≤2000 words; /super-manus:prd-update)
    ├── roadmap.md                              # project-global, module status table (auto-managed)
    ├── prd_drift.md                            # project-global, PRD ↔ implementation drift log (append-only)
    └── impl/                                   # time series of milestones, per module
        └── <module>/
            └── <YYYY-MM-DD>-<update-name>/     # only place timestamps appear
                ├── task_plan.md                # phase index for this update
                ├── findings.md                 # decisions / errors / data points for this update
                ├── progress.md                 # commits + session log for this update (hook-managed)
                └── tasks/
                    └── p<n>_impl.md            # per-phase technical plan (lazy, /super-manus:impl)
```

## What it does NOT do

v0.4 stays small. Out of scope:

- Per-module test folders (test design intent goes in `prd/<module>.md ## Quality bar`; per-day test outcomes go in the update's `findings.md`)
- Module rename command (low frequency — rename folders + edit `prd/_index.md` manually)
- Migration command from v0.2/v0.3 (manual: move files per the using-sm skill §8)
- Multi-product monorepo support in a single super-manus folder (use multiple super-manus-enabled subdirectories — one per product — or stay on v0.3)
- TDD task executor / subagent dispatch / code review / multi-harness — still deferred items
- Automated test running (use your existing toolchain)
- PR creation or merge integration

## Coexistence with superpowers

super-manus and superpowers can both be installed; they don't fight:

- super-manus owns SessionStart / Stop / PostToolUse hooks for the **state layer**.
- superpowers owns its own SessionStart hook for skill bootstrap — both fire, both inject, no conflict.
- super-manus skills don't auto-trigger; `using-sm` is invoked only when you run `/super-manus:*`.
- Plans written by superpowers' `writing-plans` (`docs/plans/*.md`) are independent of super-manus.

## Status

v0.4 — project-global PRD with module × milestone two-axis model and drift detection. See [docs/design-v0.4.md](docs/design-v0.4.md) for the full design. v0.2/v0.3 ([docs/design-v0.2.md](docs/design-v0.2.md), superseded) and v0.1 ([docs/design-v0.1.md](docs/design-v0.1.md), superseded) are kept for historical reference.
