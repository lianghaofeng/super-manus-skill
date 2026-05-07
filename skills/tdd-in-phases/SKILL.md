---
name: tdd-in-phases
description: Phase-scoped TDD discipline for super-manus v0.5. When `/super-manus:impl` enters a phase, the impl-test-writer agent commits red phase tests + e2e tests BEFORE the impl-code-writer is spawned. Tests are derived from `prd/<module>.md ## What users get` and `prd/_index.md ## Demo`, not from `tasks/p<n>_impl.md ## Approach`. Code-writer never edits or skips tests.
---

# tdd-in-phases (v0.5)

This skill is the execution-layer discipline that makes the 3-agent `/super-manus:impl` pipeline meaningful. Without it the test-writer / code-writer split collapses into theatre.

## When this skill applies

- Inside the `/super-manus:impl` and `/super-manus:impl-all` orchestrators, between the architect step and the code-writer step.
- Anywhere an agent is asked to "write tests" for a super-manus phase or for a `## What users get` capability.
- It does NOT apply to ad-hoc bug-fix sessions outside super-manus or to test scaffolding the user writes by hand.

## The non-negotiable order

v0.7 adds 3 review checkpoints driven by `impl-reviewer` (read-only, no Write/Edit). The reviewer is the loop driver — writers stay stateless, only knowing their inputs (and `previous_attempt_feedback` on re-spawn).

```
[1] impl-architect emits tasks/p<n>_impl.md            (no code, no tests)
[2] impl-reviewer (mode=pre-test) — APPROVE / RETURN_TO_ARCHITECT / ESCALATE
    counter[#1] tracks RETURNs from this checkpoint; max 2; 3rd → ESCALATE
[3] impl-test-writer emits + commits red tests         (phase tests + e2e tests)
[4] impl-reviewer (mode=pre-code) — APPROVE / RETURN_TO_TEST_WRITER / RETURN_TO_ARCHITECT / ESCALATE
    counter[#2] tracks RETURNs from this checkpoint; max 2; 3rd → ESCALATE
[5] orchestrator hashes every test file just committed (after review #2 APPROVE — never before)
    impl-code-writer emits + commits source code       (read-only on tests/ and e2e/)
[6] impl-reviewer (mode=pre-close) — APPROVE / RETURN_TO_CODE_WRITER / RETURN_TO_TEST_WRITER / RETURN_TO_ARCHITECT / ESCALATE
    counter[#3] tracks RETURNs from this checkpoint; max 2; 3rd → ESCALATE
[7] orchestrator re-hashes; mismatch → ABORT phase
[8] orchestrator runs `## Verification`; pass → close phase
```

**The temporal order is the cheat-prevention.** By the time the code-writer is spawned (Step 5), the tests are already in git AND have been APPROVEd by the reviewer. There is no "future impl" for the tests to mirror.

**The reviewer is the loop driver.** Writers do not know they are on attempt N — they read `previous_attempt_feedback` from their spawning prompt (a new optional input on re-spawn) and address each item. Per-checkpoint counters live in the orchestrator; 3 attempts max per checkpoint before ESCALATE. Reviewer can RETURN to any upstream writer (e.g. `pre-close` reviewer can `RETURN_TO_TEST_WRITER` if the failing test fixture is wrong); the orchestrator cascades — re-spawn the target writer and every downstream stage, re-hash on test re-commit, then re-invoke the originating review checkpoint.

**The reviewer cannot bypass the hash check.** Reviewer is read-only by tool surface (no Write, no Edit). Cheat-prevention semantics carry forward unchanged.

## Where phase tests live

Every phase MUST produce at least one phase test at:

```
docs/super-manus/impl/<module>/<update>/tests/phase_p<n>_<verb>_<noun>.<ext>
```

Naming rules per language:

| Runtime | Phase test path | Why |
| --- | --- | --- |
| Python (pytest) | `phase_p<n>_<verb>_<noun>.py` | pytest's default glob matches `test_*.py`; `phase_*` is silently skipped — exactly what we want |
| Node + jest | `phase_p<n>_<verb>_<noun>.phase.ts` | jest default matches `*.test.ts`; `*.phase.ts` is skipped |
| Vitest | `phase_p<n>_<verb>_<noun>.phase.ts` | same as jest |
| Rust | `tests/phase_p<n>_<verb>_<noun>.rs` (under the update folder) | Rust integration tests are placement-flexible |
| Go / Java / Maven | written at the project's required location with `phase_*` prefix preserved | Go and Maven enforce file layout; preserve the prefix so origin stays identifiable |

The naming convention is load-bearing: phase tests are deliberately invisible to default test runners. They are NOT regression tests. They prove the milestone shipped, then they archive with the update folder.

## Where e2e tests live (test-writer also writes these)

Permanent regression suite, mirrors PRD structure:

```
docs/super-manus/e2e/
├── _system/
│   └── test_<scenario>.<ext>     ← cross-module ## Demo scenarios from prd/_index.md
└── <module>/
    └── test_<capability>.<ext>   ← per-module ## What users get capabilities
```

These DO use `test_*.{ext}` naming so pytest / jest pick them up automatically. CI runs them on every commit. They live as long as the capability lives in PRD; they outlast individual update folders.

## Test source priority (test-writer reads in this order)

1. **[primary]** `prd/<module>.md` — full 9 sections; especially `## What users get`, `## Quality bar`, `## Risks`, `## Demo`. **Tests anchor here.**
2. **[primary]** `prd/_index.md` — full 8 sections; especially `## Demo`, `## Audience`, `## Success metrics`. Cross-module scenarios.
3. **[secondary]** `tasks/p<n>_impl.md ## Objective` — what this phase claims to deliver.
4. **[secondary]** `tasks/p<n>_impl.md ## Verification` — to avoid duplicating coverage already promised there.
5. **[secondary]** prior phase tests + `e2e/<module>/test_*.{ext}` — what is already covered.
6. **[context only]** `tasks/p<n>_impl.md ## Approach` and `## Files touched` — context for HOW the phase delivers, NOT a template for test structure. Mirroring `## Approach` produces tautological tests.
7. **[context only]** source code + LSP — only to learn API surface (class names, function names, route paths) so the test compiles. Do NOT shape test logic from existing code.

## Persona discipline (the load-bearing instruction)

> Tests validate the PRD spec. Tests do NOT mirror the impl plan.
>
> `## Approach` is one valid implementation among many. If the impl could plausibly take a different `## Approach` and still satisfy the same `## What users get` bullet, the test must pass with both implementations.

Concrete tells of a tautological / mirror test:

- Test imports a private helper that's named in `## Approach`.
- Test asserts on internal state (a queue's length, a cache's keys) instead of user-observable output.
- Test's expected values come from the impl's would-be return value, not from PRD's `## Quality bar` / `## Demo` / `## What users get` claims.

If the test-writer catches itself doing any of those, it should rewrite the test against the user-observable surface (HTTP response, CLI stdout, screen state, file contents) before committing.

## What test-writer commits

ONLY test files. The commit message convention:

```
test(p<n>): red phase tests + e2e for <capability>
```

The test run after the commit MUST report all newly-written tests as failing (red bar). Pre-existing e2e tests for unchanged capabilities should still pass — the test-writer's run is a sanity check on the test environment, not a green-bar attempt.

## What code-writer must NOT do

The hard rules (also stated in `agents/impl-code-writer.md`):

- MUST NOT edit any file under `docs/super-manus/impl/<m>/<u>/tests/`.
- MUST NOT edit any file under `docs/super-manus/e2e/`.
- MUST NOT add `@pytest.skip`, `it.skip(...)`, `xtest`, `--ignore`, or any other skip mechanism for a phase test or touched e2e test.
- MUST NOT delete a phase test or e2e test file.
- If a test is genuinely wrong (encodes a contradiction with PRD, has a typo that makes it un-passable in any impl), the code-writer MUST stop, append a row to `findings.md ## Errors` describing the contradiction, and surface to the user. The user resolves — either by editing the test directly, or by editing PRD (via `/super-manus:prd-update`) and re-spawning test-writer.

The orchestrator hashes every test file before the code-writer is spawned and re-hashes after. Any mismatch ABORTS the phase and appends a `code-writer modified tests for phase p<n>` drift row.

## Decision tree: write e2e this phase, or not?

For each `## What users get` bullet this phase touches:

```
is this phase the LAST phase delivering this capability?
  yes → write e2e/<module>/test_<capability>.{ext} (new or extend existing)
  no  → skip e2e for this capability this phase; the LAST phase will write it
  unsure → audit: append `(audit — capability completion uncertain)`
            note in findings.md and ask the user
```

For each `## Demo` scenario this phase completes (cross-module):

```
write e2e/_system/test_<scenario>.{ext} (new or extend existing)
```

If the test-writer is unsure whether the phase completes a `## Demo` scenario, it inspects `task_plan.md ## Phases` for remaining phases that might also touch the scenario. If none, this phase completes it.

## Karpathy guidelines

Both the test-writer and the code-writer reference `andrej-karpathy-skills:karpathy-guidelines` in their personas. The four discipline points apply directly to TDD work:

- **Surgical changes** — one phase = one focused set of tests. Don't write tests for adjacent capabilities.
- **Surface assumptions** — every `(audit)` marker is an assumption surfaced. Tests with `(audit)` reasoning go alongside tests without.
- **Define verifiable success criteria** — every phase test asserts a concrete user-observable claim.
- **Avoid overcomplication** — prefer a 5-line test that asserts the right thing over a 50-line test that asserts plumbing.
