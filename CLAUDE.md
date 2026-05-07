# Contributor Guide

This file is for AI agents (and humans) modifying the super-manus plugin itself. Read it before editing.

## Repo invariants

- Any change touching `hooks/` requires a matching `tests/test_<name>.sh`. New hook, new test — no exceptions.
- Each agent under `agents/<name>.md` needs `tests/test_agent_<name>.sh` asserting frontmatter (name/description/tools), persona, inputs, and behavioural invariants its callers rely on. Agents are spawned via `subagent_type=<name>`, so the agent's `name` frontmatter and the orchestrator's `subagent_type` must stay in lock-step.
- Each skill is a directory `skills/<name>/SKILL.md` and needs `tests/test_skill_<name>.sh` asserting the SKILL.md frontmatter (`name`, `description`) plus any load-bearing section headings the orchestrator references.
- `impl-test-writer` and `impl-code-writer` enforce the cheat-prevention boundary; their tests MUST assert the write barrier — `impl-test-writer` has no `Edit` tool; `impl-code-writer`'s persona forbids editing any file under `tests/` or `e2e/` (the orchestrator additionally hashes test files before/after to enforce mechanically).
- Templates under `templates/` MUST keep their schema headings verbatim (parsed by hooks and scripts; renaming silently breaks the runtime):
  - `task_plan.md`: `## Goal`, `## Phases`
  - `findings.md`: `## Decisions`, `## Errors`, `## Data points / research`
  - `progress.md`: `## Completed commits`, `## Session log`, `## Outstanding`
  - `phase_plan.md`: `## Objective`, `## Approach`, `## Files touched`, `## Verification`
  - `prd_index.md` (8 H2): `## Problem`, `## Audience`, `## Success metrics`, `## Demo`, `## Must`, `## Not doing`, `## Modules`, `## Data flow overview`
  - `prd_module.md` (9 H2): `## Why this exists`, `## Users`, `## Success`, `## What users get`, `## How it connects`, `## Quality bar`, `## Risks`, `## Out of scope`, `## Open questions`
  - `roadmap.md`: `## Modules`
  - `prd_drift.md`: `# PRD drift log` (single H1; the table is the body)
- `templates/prd.md` (legacy v0.1 flat-folder PRD) is kept for backward compatibility and must not be removed.
- Plugin manifest (`.claude-plugin/plugin.json`) and hook configuration (`hooks/hooks.json`) are load-bearing. Validate JSON before committing.

## Layout

```
docs/super-manus/
├── prd/                                     ← project-global, ONE source of truth
│   ├── _index.md                            ← 8 PM-flavored H2 sections, ≤700 words
│   └── <module>.md                          ← 9 PM-flavored H2 sections, ≤2000 words
├── e2e/                                     ← permanent regression suite, mirrors prd/
│   ├── _system/test_<scenario>.<ext>        ← cross-module scenarios from prd/_index.md ## Demo
│   └── <module>/test_<capability>.<ext>     ← per-module capabilities from prd/<module>.md ## What users get
├── roadmap.md                               ← project-global, module status table
├── prd_drift.md                             ← project-global, append-only drift log
└── impl/<module>/<YYYY-MM-DD>-<update>/     ← time series of milestones (only place timestamps appear)
    ├── task_plan.md
    ├── findings.md
    ├── progress.md
    ├── tasks/p<n>_impl.md
    └── tests/phase_p<n>_<verb>_<noun>.<ext> ← phase tests, milestone-scoped
```

Invariants:

- Project-global state lives at `docs/super-manus/prd/`, `docs/super-manus/roadmap.md`, `docs/super-manus/prd_drift.md`, and `docs/super-manus/e2e/`. Per-update state lives at `docs/super-manus/impl/<module>/<YYYY-MM-DD>-<update>/`; phase tests live at `docs/super-manus/impl/<module>/<update>/tests/phase_p<n>_*.<ext>`.
- PRD files are **target state** (current snapshot, no changelog markers). `git log -p prd/<module>.md` is the audit trail.
- `impl/<module>/<update>/` is the **time series**; old updates are immutable historical record.
- One project = one PRD. There is NO `.super-manus/active` state file. Hooks resolve the active update via `sm_active_update` (mtime scan of `docs/super-manus/impl/<module>/*/`); never invent a second active-state file.
- Drift between PRD and implementation is **always** logged to `prd_drift.md`; the agent must not silently update PRD.
- **Phase tests** (`tests/phase_p<n>_*.<ext>` or `*.phase.ts`) are NOT auto-discovered by default test runners — `/super-manus:impl` runs them via explicit path. Naming chosen specifically to dodge `pytest test_*.py` / `jest *.test.ts` globs.
- **e2e tests** (`e2e/<module>/test_<capability>.<ext>`, `e2e/_system/test_<scenario>.<ext>`) ARE auto-discovered. They are the permanent regression suite; CI runs them on every commit.
- End-of-update drift gate is BLOCKING with 3 passes: refresh drift from commits / e2e coverage check (every touched `## What users get` capability has a passing e2e) / pending == 0 in `prd_drift.md`. Missing or red e2e → `pending` row → blocks roadmap from flipping to `stable`.

## Architecture

- `/super-manus:impl` runs ONE phase through 4 agents with 3 review checkpoints: **impl-architect** (drafts `tasks/p<n>_impl.md`) → **impl-reviewer** [pre-test] → **impl-test-writer** (commits red phase tests + e2e) → **impl-reviewer** [pre-code] → **impl-code-writer** (writes source until tests green) → **impl-reviewer** [pre-close]. Reviewer is read-only by tool surface (no Write/Edit) and drives re-spawn loops; APPROVE / RETURN_TO_<writer> / ESCALATE_TO_USER per checkpoint, retry budget = 2 RETURNs (3rd ESCALATEs). Hash baseline for cheat-prevention is established AFTER review #2 APPROVE — never before — so cascade re-spawns (review #3 → test-writer) can re-hash on the new test commit.
- `/super-manus:impl-all` loops the same pipeline through all pending phases without pausing; loop-stops include reviewer ESCALATE_TO_USER.
- `/super-manus:prd-update <module>` is dual-mode: forward iteration (no pending drift row → user adds/tightens a bullet before coding; skip findings.md write) or drift absorption (pending row → write findings.md decision + flip Resolution). Mode auto-detected.
- Skills `tdd-in-phases` / `verification-before-phase-close` / `systematic-debugging-in-phase` are invoked by `/super-manus:impl` during phase execution. `using-sm` is the umbrella skill invoked by every `/super-manus:*` command.

## PR governance

- Small commits, one logical change per commit.
- Commit messages follow the conventional style already in `git log` (`feat:`, `fix:`, `docs:`, `chore:`, `test:`).
- Never `git push --force` to `main`. If history needs rewriting, do it on a branch and open a PR.
- Run `bash tests/run-all.sh` before declaring any task done. A green run is the bar — not "looks right to me".
- Never commit `.DS_Store`, editor swap files, or anything outside the four-file commit you intended.

## Where to look

- **Current design**: `docs/design-v0.7.md` — read this before adding anything. Covers the 4-agent reviewer pipeline (v0.7.0) and the v0.7.1 PRD-template refinements (`## How it connects` Exposes/Consumes preamble + `## Data flow overview` `(for: <capability>)` edge annotation).
- Older designs at `docs/design-v0.{1,2,4,5,6}.md` — superseded, kept for historical reference only. Don't read unless you need to understand WHY a current invariant exists.
- Per-task implementation plans live at `docs/plans/`.
