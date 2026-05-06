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
