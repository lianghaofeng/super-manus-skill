# Contributor Guide

This file is for AI agents (and humans) modifying the super-manus plugin itself. Read it before editing.

## Repo invariants

- Any change touching `hooks/` requires a matching `tests/test_<name>.sh`. New hook, new test — no exceptions.
- Same rule for `agents/`: each agent under `agents/<name>.md` needs `tests/test_agent_<name>.sh` asserting its frontmatter (name/description/tools), persona, inputs, and any behavioural invariants its callers rely on. Agents are spawned by slash commands via the Agent tool with `subagent_type=<name>`, so the agent's `name` frontmatter and the orchestrator's `subagent_type` must stay in lock-step.
- Templates under `templates/` must keep their schema headings verbatim. The full set in v0.2:
  - `task_plan.md`: `## Goal`, `## Phases`
  - `findings.md`: `## Decisions`, `## Errors`, `## Data points / research`
  - `progress.md`: `## Completed commits`, `## Session log`, `## Outstanding`
  - `phase_plan.md`: `## Objective`, `## Approach`, `## Files touched`, `## Verification`
  - `prd_index.md` (v0.2 PM-flavored, **8 H2 sections**): `## Problem`, `## Audience`, `## Success metrics`, `## Demo`, `## Must`, `## Not doing`, `## Modules`, `## Data flow overview`
  - `prd_module.md` (v0.2 PM-flavored, **9 H2 sections**): `## Why this exists`, `## Users`, `## Success`, `## What users get`, `## How it connects`, `## Quality bar`, `## Risks`, `## Out of scope`, `## Open questions`
  - **Schema migration note**: the previous v0.2 used 6-section technical headings (Purpose / Surface / Data flow / Constraints / Out of scope / Open questions on per-module; Problem / Demo / Must / Not doing / Modules / Data flow overview on `_index.md`). The PM-flavored set above replaces it everywhere — parsers, tests, agents, slash commands — there is no dual-mode acceptance.
  - `roadmap.md` (v0.2): `## Modules`
  - `prd_drift.md` (v0.2): `# PRD drift log` (single H1; the table is the body)
  - These headings are parsed by hooks and scripts; renaming them silently breaks the runtime.
- v0.1 templates (`templates/prd.md` — the flat-folder PRD) are kept for legacy v0.1 features and must not be removed; v0.2/v0.4 use `prd_index.md` + `prd_module.md` instead.
- Plugin manifest (`.claude-plugin/plugin.json`) and hook configuration (`hooks/hooks.json`) are load-bearing. Validate JSON before committing.

## v0.4 layout (PROJECT-GLOBAL PRD; current target)

The v0.3 layout wrapped everything in a per-feature timestamped folder (`docs/super-manus/<YYYY-MM-DD>-<feature>/`) which conflated two concepts: the PRD (a current-state snapshot of the project) and the impl time-series (per-update milestones). v0.4 separates them:

```
docs/super-manus/
├── prd/                                     ← project-global, ONE source of truth
│   ├── _index.md                            ← 8 PM-flavored H2 sections
│   └── <module>.md                          ← 9 PM-flavored H2 sections
├── roadmap.md                               ← project-global, module status table
├── prd_drift.md                             ← project-global, append-only drift log
└── impl/                                    ← time series of milestones, per module
    └── <module>/
        └── <YYYY-MM-DD>-<update-name>/      ← only place timestamps appear
            ├── task_plan.md
            ├── findings.md
            ├── progress.md
            └── tasks/
                └── p<n>_impl.md
```

Invariants:
- PRD files are **target state** (current snapshot, no changelog markers).
- `impl/<module>/<update>/` is the **time series**; old updates are immutable historical record.
- There is NO `.super-manus/active` state file in v0.4. Hooks resolve the active update purely via `sm_active_update` (mtime scan of `docs/super-manus/impl/<module>/*/`) — never invent a second active-state file.
- Drift between PRD and implementation is **always** logged to `prd_drift.md`; the agent must not silently update PRD.
- The "feature" abstraction is gone. There is one project = one PRD. Multi-product monorepos must use multiple super-manus-enabled subdirectories (one per product) or stay on v0.3.

## v0.3 → v0.4 path migration

| v0.3 path | v0.4 path |
| --- | --- |
| `docs/super-manus/<feature>/prd/_index.md` | `docs/super-manus/prd/_index.md` |
| `docs/super-manus/<feature>/prd/<module>.md` | `docs/super-manus/prd/<module>.md` |
| `docs/super-manus/<feature>/roadmap.md` | `docs/super-manus/roadmap.md` |
| `docs/super-manus/<feature>/prd_drift.md` | `docs/super-manus/prd_drift.md` |
| `docs/super-manus/<feature>/impl/<m>/<u>/` | `docs/super-manus/impl/<m>/<u>/` |
| `.super-manus/active` (feature folder name) | (removed; mtime resolve only) |

Slash command surface area also shrinks: `/super-manus:start` becomes a no-arg "enable in this project" command, `/super-manus:switch` is removed, `/super-manus:phase` (legacy v0.1) is removed. `/super-manus:catchup` re-injects the most-recently-modified update's task_plan plus the project-global `prd/_index.md`.

## PR governance

- Small commits, one logical change per commit.
- Commit messages follow the conventional style already in `git log` (`feat:`, `fix:`, `docs:`, `chore:`, `test:`).
- Never `git push --force` to `main`. If history needs rewriting, do it on a branch and open a PR.
- Run `bash tests/run-all.sh` before declaring any task done. A green run is the bar — not "looks right to me".
- Never commit `.DS_Store`, editor swap files, or anything outside the four-file commit you intended.

## Where to look

- **Current design** lives in `docs/design-v0.4.md` — source of truth for the project-global layout and the active development target.
- v0.2/v0.3 design is preserved at `docs/design-v0.2.md` for historical reference (with a SUPERSEDED banner — its layout invariants no longer apply).
- v0.1 design is preserved at `docs/design-v0.1.md` for historical reference (with a SUPERSEDED banner).
- Plans (task-by-task implementation breakdown) live in `docs/plans/`.
- When in doubt about scope or layout, re-read `design-v0.4.md` before adding anything.
