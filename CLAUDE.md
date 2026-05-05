# Contributor Guide

This file is for AI agents (and humans) modifying the super-manus plugin itself. Read it before editing.

## Repo invariants

- Any change touching `hooks/` requires a matching `tests/test_<name>.sh`. New hook, new test — no exceptions.
- Templates under `templates/` must keep their schema headings verbatim. The full set in v0.2:
  - `task_plan.md`: `## Goal`, `## Phases`
  - `findings.md`: `## Decisions`, `## Errors`, `## Data points / research`
  - `progress.md`: `## Completed commits`, `## Session log`, `## Outstanding`
  - `phase_plan.md`: `## Objective`, `## Approach`, `## Files touched`, `## Verification`
  - `prd_index.md` (v0.2): `## Problem`, `## Demo`, `## Must`, `## Not doing`, `## Modules`, `## Data flow overview`
  - `prd_module.md` (v0.2): `## Purpose`, `## Surface`, `## Data flow`, `## Constraints`, `## Out of scope`, `## Open questions`
  - `roadmap.md` (v0.2): `## Modules`
  - `prd_drift.md` (v0.2): `# PRD drift log` (single H1; the table is the body)
  - These headings are parsed by hooks and scripts; renaming them silently breaks the runtime.
- v0.1 templates (`templates/prd.md` — the flat-folder PRD) are kept for legacy v0.1 features and must not be removed; v0.2 uses `prd_index.md` + `prd_module.md` instead.
- Plugin manifest (`.claude-plugin/plugin.json`) and hook configuration (`hooks/hooks.json`) are load-bearing. Validate JSON before committing.
- The two-axis v0.2 model has its own invariants:
  - PRD files are **target state** (current snapshot, no changelog markers).
  - `impl/<module>/<update>/` is the **time series**; old updates are immutable historical record.
  - Hooks resolve the active update via `sm_active_update <feature>` (in `hooks/lib.sh`) — never invent a second active-state file.
  - Drift between PRD and implementation is **always** logged to `prd_drift.md`; the agent must not silently update PRD.

## PR governance

- Small commits, one logical change per commit.
- Commit messages follow the conventional style already in `git log` (`feat:`, `fix:`, `docs:`, `chore:`, `test:`).
- Never `git push --force` to `main`. If history needs rewriting, do it on a branch and open a PR.
- Run `bash tests/run-all.sh` before declaring any task done. A green run is the bar — not "looks right to me".
- Never commit `.DS_Store`, editor swap files, or anything outside the four-file commit you intended.

## Where to look

- **Current design** lives in `docs/design-v0.2.md` — the source of truth for v0.2 and the active development target.
- v0.1 design is preserved at `docs/design-v0.1.md` for historical reference (with a SUPERSEDED banner).
- Plans (task-by-task implementation breakdown) live in `docs/plans/`.
- When in doubt about scope, re-read `design-v0.2.md §3` (Scope) and `§12` (Out-of-scope clarifications) before adding anything.
