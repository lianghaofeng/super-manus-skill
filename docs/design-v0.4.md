# super-manus — Design Doc (v0.4)

> Current design. Validated through brainstorming session 2026-05-07.
>
> Supersedes [docs/design-v0.2.md](design-v0.2.md) (v0.2/v0.3 — per-feature wrapper folder layout) and [docs/design-v0.1.md](design-v0.1.md) (v0.1 — flat single-PRD layout).

## 1. What changed from v0.3

v0.3 wrapped everything in a per-feature timestamped folder:

```
docs/super-manus/2026-05-07-<feature-name>/
  ├── prd/
  ├── impl/
  ├── roadmap.md
  └── prd_drift.md
```

This conflated two concepts that should be separate:

- **PRD** describes the system **as it currently exists** (target-state snapshot, one source of truth)
- **impl** describes **work-in-progress on the system** (time series of milestone updates)

Wrapping PRD inside a `<date>-<feature>/` folder implied PRD belongs to a moment in time — directly contradicting "PRD is current-state". It also forced the user to remember a feature name when starting a new milestone or running drift checks.

**v0.4 hoists PRD / roadmap / prd_drift to project-global level. Time only lives in `impl/<module>/<YYYY-MM-DD>-<update-name>/`.**

Concrete layout:

```
docs/super-manus/
├── prd/                                     ← project-global, ONE source of truth
│   ├── _index.md                            ← 8 PM-flavored H2 sections
│   └── <module>.md                          ← 9 PM-flavored H2 sections
├── roadmap.md                               ← project-global
├── prd_drift.md                             ← project-global, append-only
└── impl/                                    ← time series of milestones, per module
    └── <module>/
        └── <YYYY-MM-DD>-<update-name>/
            ├── task_plan.md
            ├── findings.md
            ├── progress.md
            └── tasks/
                └── p<n>_impl.md
```

Key consequences:

- **`.super-manus/active` is removed.** Hooks resolve the active update purely via `sm_active_update` (mtime scan of `docs/super-manus/impl/<module>/*/`). One less state file to keep in sync.
- **The "feature" abstraction is gone.** One project = one PRD. Multi-product monorepos use multiple super-manus-enabled subdirectories (one per product).
- **`/super-manus:start` is now no-arg, idempotent.** It enables super-manus in the current directory by creating `docs/super-manus/{prd,impl}/` and seeding `prd/_index.md` + `roadmap.md` + `prd_drift.md` from templates.
- **`/super-manus:switch` is removed** (no features to switch between).
- **`/super-manus:phase` is removed** (legacy v0.1 command, replaced by `/super-manus:impl`).
- **`/super-manus:catchup`** re-injects the most-recently-modified update's `task_plan.md` plus the project-global `prd/_index.md`.

## 2. Core principles (unchanged from v0.2/v0.3)

1. **PRD is module target state.** Revised only via `/super-manus:prd-update <module>` (minimum surgical edit, no changelog markers). PRD reads like a product snapshot, not a changelog.
2. **impl is module timeline.** Each milestone update is a folder with a date prefix; old updates are immutable historical record, the latest is active.
3. **PRD ↔ implementation alignment is enforced.** When implementation diverges from PRD, the agent stops, logs to `prd_drift.md`, and asks the user: revert implementation, or update PRD?
4. **Reuse v0.1/v0.2 internals verbatim.** Per-update four-file set unchanged; PM-flavored 9+8 PRD heading set from v0.3 unchanged.

## 3. PRD heading schema (PM-flavored, unchanged from v0.3)

Per-module file (`prd/<module>.md`, 9 H2 sections, ≤2000 words):

| # | Heading | Role |
| --- | --- | --- |
| 1 | `## Why this exists` | 2 sentences, PM voice — pain + business value |
| 2 | `## Users` | persona + trigger moment |
| 3 | `## Success` | measurable user-facing outcomes |
| 4 | `## What users get` | 3–5 capabilities, PM voice + technical evidence ("Backed by:") |
| 5 | `## How it connects` | upstream / downstream / third-party + edge list |
| 6 | `## Quality bar` | user-visible NFRs (perf, scale, compliance) |
| 7 | `## Risks` | Product / Technical / Org+dependency, three categories |
| 8 | `## Out of scope` | explicit non-goals |
| 9 | `## Open questions` | each item: [decide\|clarify\|measure] + Resolution criterion |

Project-level file (`prd/_index.md`, 8 H2 sections, ≤700 words):

| # | Heading | Role |
| --- | --- | --- |
| 1 | `## Problem` | one sentence pain statement |
| 2 | `## Audience` | primary + secondary users |
| 3 | `## Success metrics` | top 3 KPIs with target + measurement |
| 4 | `## Demo` | 3–5 line concrete usage scenario |
| 5 | `## Must` | feature-level capabilities |
| 6 | `## Not doing` | explicit non-goals |
| 7 | `## Modules` | table linking to per-module PRD files |
| 8 | `## Data flow overview` | ASCII architecture diagram + edge list + offline-modules line + 1–2 sentence loop summary |

## 4. Slash command surface (8 commands, down from 11)

| Command | Role |
| --- | --- |
| `/super-manus:start` | (no args) idempotent enable in current project |
| `/super-manus:brainstorm` | 6-question Q&A producing PRD content; does NOT auto-seed update folder |
| `/super-manus:reverse-prd` | one-shot scan of existing project, generates PRD via `reverse-prd-architect` agent |
| `/super-manus:sync <module>` | reads PRD-diff to detect new capability, drafts Phases via `sync-planner` agent, scaffolds update folder |
| `/super-manus:impl` | resumes work on active update, drafts phase plan via `impl-architect` agent, runs drift check, executes |
| `/super-manus:prd-update <module>` | surgical PRD edit to absorb confirmed implementation deviation |
| `/super-manus:drive` | global "what should I do next" decider with drift scan |
| `/super-manus:catchup` | re-inject most-recent update's task_plan + project-global PRD index into context |
| `/super-manus:log` | manual session log entry |

Removed in v0.4: `/super-manus:switch` (no features), `/super-manus:phase` (legacy v0.1).

## 5. Agent architecture

Three named agents under `agents/`:

- **`reverse-prd-architect`** — chief system architect + senior PM. Reads project sources, produces full PRD bundle (`prd/_index.md` + per-module files) with mandatory ASCII architecture diagram. Spawned by `/super-manus:reverse-prd` after Stage 1 module discovery.
- **`sync-planner`** — senior tech lead. Reads PRD diff + existing module surface, drafts a 3–6 phase decomposition with `(audit)` markers on uncertain phases. Spawned by `/super-manus:sync` after the diff signal is gathered.
- **`impl-architect`** — senior implementation planner. Reads module PRD + task_plan + findings + progress, drafts the next phase's `tasks/p<n>_impl.md` (Objective / Approach / Files touched / Verification). Spawned by `/super-manus:impl` after the drift check passes.

Each agent has its own test (`tests/test_agent_<name>.sh`) per the CLAUDE.md repo invariant.

## 6. Drift control

Three trigger points (unchanged from v0.3):

- `/super-manus:sync` — reads PRD diff. Drift is impossible by construction (the diff IS the milestone intent). Special-case: deletion from `## What users get` → redirect to `/super-manus:prd-update`.
- `/super-manus:impl` — before spawning `impl-architect`, runs Drift check protocol: phase intent vs PRD `## What users get` / `## Quality bar` / `## Out of scope`.
- `/super-manus:drive` — global drift scan: recent commits ↔ PRD.

**End-of-update drift gate (BLOCKING)** — when all phases of an update are `closed`, `/super-manus:impl` runs a two-pass gate:

1. Refresh drift from this update's commits (declared-but-not-built, built-but-not-declared).
2. Read `docs/super-manus/prd_drift.md`. Count rows where `Module=<this>` AND `Resolution=pending`.
   - `pending > 0` → BLOCKED. Print rows; suggest `/super-manus:prd-update` or revert + `Resolution=reverted` + findings entry. STOP. Do NOT flip roadmap.
   - `pending == 0` → flip roadmap row from `iterating` to `stable`. Update done.

`/super-manus:prd-update` flips a row's Resolution from `pending` to `prd-update: <option-letter>`, which automatically unblocks the gate on next `/super-manus:impl` invocation.

## 7. Migration from v0.3

Manual migration (no script provided):

1. Move `docs/super-manus/<feature>/prd/` → `docs/super-manus/prd/`
2. Move `docs/super-manus/<feature>/roadmap.md` → `docs/super-manus/roadmap.md`
3. Move `docs/super-manus/<feature>/prd_drift.md` → `docs/super-manus/prd_drift.md`
4. Move `docs/super-manus/<feature>/impl/` → `docs/super-manus/impl/`
5. Delete `.super-manus/active` if it exists
6. Delete the now-empty `docs/super-manus/<feature>/` folder

For projects with multiple v0.3 features in the same repo, pick the active one and migrate it; archive the others under `docs/super-manus-archive/<feature>/` if you need to retain history.

## 8. Out-of-scope (v0.4)

- Multi-product support inside a single super-manus-enabled folder (use multiple folders, one per product)
- Automatic v0.3 → v0.4 migration script
- Cross-language LSP normalization (still leans on whichever LSP server Claude Code provides)
- Metric-pipeline integration for `## Success metrics` (PRD records targets; measurement is up to the project's existing observability stack)

## 9. Plugin version

v0.4.0 (breaking layout change vs v0.3). Plugin manifest at `.claude-plugin/plugin.json` is the canonical version source.
