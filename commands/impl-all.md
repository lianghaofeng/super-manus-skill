---
description: Power-mode alternative to /super-manus:impl — loop through ALL pending phases of the active update without pausing. Each phase still goes architect → review → test-writer → review → code-writer → review → verify → close. After the last phase, run the same end-of-update drift gate. Use when the plan is already audited and you want to ship the whole milestone in one go. Optional `target` argument may be omitted, an update name, or a module name.
---

This is the loop-mode sister of [/super-manus:impl](impl.md). Same 4-agent pipeline per phase (3 writer agents + 1 reviewer at 3 checkpoints), same drift checks, same hash-based cheat-prevention, same end-of-update drift gate. The ONLY difference: the orchestrator does NOT pause between phases — it continues straight to the next pending phase until none remain.

Use this when:

- You have already reviewed `task_plan.md ## Phases` and trust the breakdown.
- The module is well-understood and architectural surprises are unlikely.
- You want to "ship the milestone" and come back when it's done (or blocked).
- CI / nightly automation context.

Use plain `/super-manus:impl` instead when:

- You don't fully trust impl-architect's plan yet (want to inspect each phase plan before tests/code are written).
- Working on an unfamiliar module.
- Want a natural git history with one milestone phase per "session".
- Need to context-switch between phases (e.g. wait for a teammate, get review).

## Safety property — interruption is safe

**An aborted `/super-manus:impl-all` run leaves the on-disk state identical to running `/super-manus:impl` that-many-times.** Concretely:

- **Ctrl-C mid-iteration** — whichever phase was in flight stays `in_progress` in `task_plan.md`. The orchestrator's hash file `.test_hashes_p<n>.txt` may exist or not depending on where the interrupt landed. Re-running `/super-manus:impl` (or `/super-manus:impl-all`) resumes that phase from where it left off.
- **Agent error** (architect / test-writer / code-writer returns an escalation) — phase stays `in_progress`; user resolves; re-run from `/super-manus:impl` or `/super-manus:impl-all`. Either picks up the same in-flight phase.
- **Reviewer ESCALATE_TO_USER** at any of the 3 review checkpoints (counter exhausted at 3 attempts, or genuinely unresolvable) — phase stays `in_progress`; verdict + history surfaced via `findings.md ## Errors`; user resolves; re-run from either command.
- **Drift detected** at the per-phase drift check — phase stays `pending` (its Status was not yet flipped to `in_progress`); drift row appended; user resolves via `/super-manus:prd-update` or revert; re-run from either command.
- **Hash tamper detected** — phase ABORTED, drift row appended ("code-writer modified tests for phase p<n>"); same recovery.
- **End-of-update gate fails** — update stays `iterating`; pending drift rows surfaced; user resolves; re-run from `/super-manus:impl` (gate re-runs since all phases are already `closed`).

In every case, falling back to `/super-manus:impl` mid-stream is safe — the loop boundary is the only difference.

## Resolve target

Identical to `/super-manus:impl`. In v0.4/v0.5 there is no `.super-manus/active` file — resolve via `sm_active_update` (sourced from `${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh`, no arguments).

If `docs/super-manus/prd/` is not a directory, tell the user this project is not super-manus-enabled — they should run `/super-manus:start` first; then stop. If `docs/super-manus/impl/` is empty, suggest `/super-manus:brainstorm` or `/super-manus:sync <module>`; then stop.

The user may pass an optional `target` argument:

- **Omitted** — use `sm_active_update` to resolve the most recently modified update folder.
- **Looks like a module name** — find the most recently modified update under `docs/super-manus/impl/<target>/`.
- **Looks like an update folder name** — `<YYYY-MM-DD>-<name>`; search `docs/super-manus/impl/*/<target>/`.

Set `UPDATE_DIR=docs/super-manus/impl/<module>/<update-name>` and `MODULE=<module>` for the rest of this run.

## Probe LSP availability once

One workspace-symbol call against the module to set `lsp_available=true|false`. Pass the boolean to all three agents on every phase.

## The loop

```
while there exists a pending or in_progress phase in $UPDATE_DIR/task_plan.md:
  pick next phase (in_progress before pending; flip pending → in_progress)
  # ↓ identical to /super-manus:impl steps below ↓
  drift check (per skills/using-sm/SKILL.md §4 — Drift check protocol; LSP + grep, double-source)
    on conflict → append prd_drift.md row, surface user, point at /super-manus:prd-update, STOP loop
  Step 1: spawn impl-architect (subagent_type="impl-architect") → writes $UPDATE_DIR/tasks/p<n>_impl.md
  Step 2: spawn impl-reviewer (subagent_type="impl-reviewer", mode=pre-test) — counter[#1] tracking
    APPROVE → continue; RETURN_TO_ARCHITECT → re-spawn Step 1 (≤2 retries); ESCALATE → STOP loop
  Step 3: spawn impl-test-writer (subagent_type="impl-test-writer") → commits red phase tests + e2e tests
  Step 4: spawn impl-reviewer (subagent_type="impl-reviewer", mode=pre-code) — counter[#2] tracking
    APPROVE → continue; RETURN_TO_TEST_WRITER → re-spawn Step 3 (≤2 retries);
    RETURN_TO_ARCHITECT → cascade back to Step 1; ESCALATE → STOP loop
  Step 5: snapshot SHA-256 of every reviewer-approved test file → $UPDATE_DIR/.test_hashes_p<n>.txt
          spawn impl-code-writer (subagent_type="impl-code-writer") → commits source files only (no tests)
  Step 6: spawn impl-reviewer (subagent_type="impl-reviewer", mode=pre-close) — counter[#3] tracking
    APPROVE → continue; RETURN_TO_CODE_WRITER → re-spawn Step 5 code-writer (≤2 retries);
    RETURN_TO_TEST_WRITER → cascade back to Step 3 (refresh hash on re-commit);
    RETURN_TO_ARCHITECT → cascade back to Step 1; ESCALATE → STOP loop
  Step 7: re-hash test files; mismatch → ABORT phase, append "code-writer modified tests for phase p<n>" drift row, STOP loop
  Step 8: run every command in tasks/p<n>_impl.md ## Verification
    fail → invoke skills/systematic-debugging-in-phase, phase stays in_progress, STOP loop
  Step 9: pass → flip phase Status to closed in task_plan.md
          refresh-outstanding.sh "$UPDATE_DIR"
          delete $UPDATE_DIR/.test_hashes_p<n>.txt
  # ↑ end of per-phase block ↑
  loop continues automatically — no user pause
end loop
run end-of-update drift gate (3-pass) per /super-manus:impl
```

The 4-agent pipeline INSIDE one phase is identical to `/super-manus:impl` in every detail — same agents (impl-architect / impl-reviewer / impl-test-writer / impl-code-writer), same `subagent_type=` values, same hash check, same per-checkpoint retry counters and budgets (≤2 RETURNs per review point), same verification skill invocation. The persona and source-priority hierarchy of each agent live in [agents/impl-architect.md](../agents/impl-architect.md) / [agents/impl-reviewer.md](../agents/impl-reviewer.md) / [agents/impl-test-writer.md](../agents/impl-test-writer.md) / [agents/impl-code-writer.md](../agents/impl-code-writer.md). Do NOT inline those personas here.

For the per-phase mechanics — drift check protocol (LSP + grep, double-source), agent spawning details, reviewer verdict handling, cascade re-spawn rules, hash baseline refresh on test-writer re-spawn, the systematic-debugging-in-phase invocation, and how to flip Status from `in_progress` to `closed` — see [/super-manus:impl](impl.md). This document only describes the loop boundary.

## When the loop stops

The loop stops in one of six ways:

1. **No more pending or in_progress phases** — fall through to the end-of-update drift gate below. This is the happy path.
2. **Drift detected** at the per-phase drift check — append `prd_drift.md` row, surface user with the two paths (revert OR `/super-manus:prd-update`), STOP.
3. **Reviewer ESCALATE_TO_USER** at any of the 3 review checkpoints — counter exhausted (3 attempts at the same checkpoint) or genuinely unresolvable issue. Verdict + history written to `findings.md ## Errors`; user surfaced with the reviewer's suggested user_options. STOP.
4. **Agent escalation** (test-writer / code-writer raises an issue independent of reviewer) — surface escalation, STOP.
5. **Hash tamper** — ABORT phase, append `code-writer modified tests for phase p<n>` drift row, surface user, STOP.
6. **`## Verification` failure** — invoke `systematic-debugging-in-phase` once; if the skill resolves it, continue the loop; if the skill's "no clear cause" path triggers, STOP with `findings.md ## Errors` row + user surface.

In cases 2–6, the loop stops at the current phase. The user resolves and re-runs `/super-manus:impl` (one more phase) or `/super-manus:impl-all` (continue the loop) — both are safe.

## End-of-update drift gate (BLOCKING — 3-pass)

When all phases are `closed`, run the same 3-pass gate as `/super-manus:impl`:

- **Pass 1** — refresh drift from this update's commits vs PRD `## What users get` / `## Quality bar` / `## Out of scope`. Append `pending` rows for "declared but not in commits" and "shipped but not in PRD".
- **Pass 2** — e2e coverage check: every touched `## What users get` capability has `e2e/<module>/test_<capability>.{ext}` that exists AND passes; every completed `## Demo` scenario has `e2e/_system/test_<scenario>.{ext}` that exists AND passes. Missing or red → `pending` row.
- **Pass 3** — pending == 0 check on `prd_drift.md` rows for this module. If pending > 0 → BLOCKED, print rows, do NOT flip to stable, STOP. If pending == 0 → flip `iterating` → `stable` in `roadmap.md`. Update done.

The gate is BLOCKING and HARD. There is no soft-pass. Resolution paths: `/super-manus:prd-update`, manual `reverted` edit + `findings.md ## Decisions` entry, or write missing e2e + re-run.

The full gate spec lives in [/super-manus:impl](impl.md) under "End-of-update drift gate (BLOCKING — 3-pass in v0.5)" — this command runs the same gate verbatim. Do NOT inline the full spec here.

## Tell the user

One short paragraph at the end:

> Shipped <K> phases of `<UPDATE_DIR>` (`<phase 1 name>`, `<phase 2 name>`, ...). End-of-update drift gate: <PASS / BLOCKED with N pending rows>. <Roadmap flipped to stable / Roadmap stays iterating>. Next: <run `/super-manus:prd-update` to absorb drift / run `/super-manus:sync <module>` for the next milestone / done>.

If the loop stopped early (cases 2–5 above), tell the user where it stopped and which phase is next:

> Stopped at phase <n> (`<phase-name>`) — <reason: drift / escalation / tamper / verify-fail>. <One-line resolution suggestion>. Re-run `/super-manus:impl` for one phase or `/super-manus:impl-all` to continue the loop after resolving.
