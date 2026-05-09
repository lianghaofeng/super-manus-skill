<!-- Per-phase implementation plan. Lazy-created by impl-architect (spawned from /super-manus:impl). Headings are stable. -->
<!-- This is where engineering detail lives: code, pseudo-code, file diffs, **DB schema, API endpoints, interface contracts**. Product spec stays in prd.md; task_plan.md stays a phase index. -->
# Phase <n>: <phase name>

## Objective

<one paragraph: what "done" means for this phase, in plain English>

## Approach

<the chosen technical route: bullets, ordered steps, or short prose. Code snippets, pseudo-code, file diffs, DB schema, API endpoints, interface contracts all live here.>

## Edge cases

<3–5 bullets. Each bullet names a concrete edge / boundary / failure case this phase MUST handle, anchored in PRD `## Quality bar` or `## Risks` (or, for tech-internal phases, a specific failure mode). NOT vague labels like "error_handling: yes". Each bullet is a checklist item the test-writer must cover with at least one assertion.>

<!--
Examples (good):
  - Empty input file (zero records) — anchored in PRD ## Quality bar "graceful on empty corpora"
  - Duplicate IDs across sources — concrete failure mode: silent overwrite would lose the second record
  - Network timeout mid-batch — anchored in PRD ## Risks "partial-batch failure must not corrupt state"

Examples (bad — will be rejected by reviewer pre-test):
  - "Error handling" (vague, untestable)
  - "Edge cases will be considered" (no enumeration)
  - "Standard validation" (no concrete failure named)

If a phase is genuinely a pure happy-path delivery (rare — usually only true for trivial scaffolding), state so explicitly with one bullet:
  - Pure happy-path scaffolding; no edge case enumeration possible at this phase. (Reviewer may RETURN if it disagrees.)

(audit) markers are allowed for cases the architect suspects but cannot confirm without coding. Reviewer MUST see them resolved before pre-test APPROVE.
-->

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
