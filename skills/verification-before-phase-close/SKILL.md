---
name: verification-before-phase-close
description: A super-manus phase Status flips from `in_progress` to `closed` ONLY after every command listed under `tasks/p<n>_impl.md ## Verification` exits green. The orchestrator (not the code-writer) runs them. Failed verify triggers the `systematic-debugging-in-phase` skill; phase stays `in_progress`. `## Verification` MUST include both a phase-test command and a user-visible smoke command.
---

# verification-before-phase-close (v0.5)

This skill is the gate at phase close. Without it, the code-writer's "all phase tests pass" claim is unverified — and a green test run is not the same as a working capability.

## When this skill applies

- After the impl-code-writer returns from a successful run inside `/super-manus:impl` (or `/super-manus:impl-all`).
- Before the orchestrator flips the phase row in `task_plan.md ## Phases` from `in_progress` to `closed`.

## Who runs verification

The **orchestrator**, not the code-writer. Reasons:

- The code-writer just emitted the code under test. Its self-report ("looks good to me") has the same trust level as a developer saying "works on my machine".
- Verification commands often touch external systems (start a server, hit an endpoint, run a CLI). The code-writer's tool budget shouldn't be spent on smoke runs.
- Centralising verification at the orchestrator keeps the abort path simple: one place to escalate, one place to log to `findings.md ## Errors`.

## What `## Verification` must contain

The architect (and the user, when auditing the plan) MUST ensure `tasks/p<n>_impl.md ## Verification` includes at minimum:

1. **Phase-test command** — a literal command line that runs the phase tests for this phase. Examples:
   - Python: `pytest docs/super-manus/impl/<m>/<u>/tests/phase_p<n>_*.py -v`
   - Node: `npx jest docs/super-manus/impl/<m>/<u>/tests/phase_p<n>_*.phase.ts`
   - Rust: `cargo test --test phase_p<n>_*`
2. **User-visible smoke command** — one command that exercises the capability the way a user (or downstream caller) would. Examples:
   - `curl http://localhost:8080/api/wiki/practice?q=...` and visually confirm the response body.
   - `python -m mycli search "query"` and confirm the stdout shows the new capability.
   - "Open `http://localhost:3000/practice`, click Submit, expect ranked answers within 2s."

A `## Verification` section that has only unit-test invocations is insufficient. Unit tests prove the implementation passes ITS tests; the smoke command proves the capability works end-to-end. Both are required.

For internal-only phases (refactor, infra), the smoke command is the regression command — "running the existing CLI exits 0; the previously-passing eval still scores ≥X". Phrase it user-observably.

## Run protocol

For each command in `## Verification`:

1. Print the command verbatim before running.
2. Run it. Capture exit code.
3. If exit code is 0 AND output matches the stated expectation (the bullet's `you should see <observable>` clause), mark the bullet ok.
4. If exit code is non-zero OR output does not match, the verify step has FAILED. STOP. Do NOT mark the phase closed. Invoke the `systematic-debugging-in-phase` skill.

For manual bullets (`open URL, click X`), the orchestrator prompts the user once to confirm the observable was seen. Trust the user's response; do not block on un-automatable steps.

## On failure

When any verification command fails:

- Phase stays `in_progress` in `task_plan.md`. Do NOT flip to `closed`. Do NOT flip to `blocked` either — `blocked` is reserved for external-dependency stalls, not for "code didn't pass verify".
- Invoke `systematic-debugging-in-phase` per its checklist.
- After the debugging skill produces a fix (or escalates to the user), re-run ALL `## Verification` commands from the top — not just the one that failed. A fix can introduce new regressions in earlier verification steps.

## On pass

When every `## Verification` command exits green and every observable matches:

1. Edit `task_plan.md ## Phases` to flip the phase row's Status from `in_progress` to `closed`.
2. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/refresh-outstanding.sh" "$UPDATE_DIR"` to regenerate `progress.md ## Outstanding`.
3. Tell the user: phase shipped, which is next (or fall through to the end-of-update drift gate if no phases remain).

## What this skill does NOT cover

- **Test cheating detection** — that's the orchestrator's hash check between test-writer and code-writer (see `tdd-in-phases`).
- **PRD↔code drift** — that's the end-of-update drift gate (see `commands/impl.md` §"End-of-update drift gate").
- **Ad-hoc smoke checks** outside super-manus — this skill is bound to the phase-close handshake.

## Karpathy guidelines connection

`## Verification` is the literal "define verifiable success criteria" point from `andrej-karpathy-skills:karpathy-guidelines`. Without it, "phase done" is a feeling. With it, "phase done" is a green exit code and a user-observable confirmation.
