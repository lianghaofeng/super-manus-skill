<!-- Per-phase implementation plan. Lazy-created by impl-architect (spawned from /super-manus:impl). Headings are stable. -->
<!-- This is where engineering detail lives: code, pseudo-code, file diffs, **DB schema, API endpoints, interface contracts**. Product spec stays in prd.md; task_plan.md stays a phase index. -->
# Phase <n>: <phase name>

## Objective

<one paragraph: what "done" means for this phase, in plain English>

## Approach

<the chosen technical route: bullets, ordered steps, or short prose. Code snippets, pseudo-code, file diffs, DB schema, API endpoints, interface contracts all live here.>

## Files touched

- `path/to/file` — <one-line reason>
- `${update_dir}/tests/phase_p<n>_<verb>_<noun>.<ext>` (new) — phase test, written by impl-test-writer

## Verification

<MUST include (1) explicit phase-test path command — e.g. `pytest ${update_dir}/tests/phase_p<n>_*.py` — AND (2) one user-visible smoke command. Do NOT name a target from the project's existing regression suite (apps/<m>/tests/, docs/super-manus/e2e/) as the phase's primary command — those run in CI on their own; phase tests are milestone-scoped and not auto-discovered.>

<!--
This section MUST include at minimum:
1. The path command for this phase's tests, e.g. for Python:
     pytest docs/super-manus/impl/<m>/<u>/tests/phase_p<n>_*.py
   or for Node/TS:
     jest docs/super-manus/impl/<m>/<u>/tests/phase_p<n>_*.phase.ts
   (substitute the project's test runner — phase tests are NOT auto-discovered;
   they must be invoked by explicit path.)
2. One user-visible smoke command — curl an endpoint, run a CLI, open a page —
   that confirms the capability works end-to-end, not just in unit tests.
The orchestrator runs every command in this section verbatim before flipping
phase Status to closed; if any exits non-zero, systematic-debugging-in-phase
kicks in and the phase stays in_progress.
-->
