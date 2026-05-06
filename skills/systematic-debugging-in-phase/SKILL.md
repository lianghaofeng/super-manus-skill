---
name: systematic-debugging-in-phase
description: Five-step checklist the super-manus orchestrator (and the impl-code-writer) follows when a phase test or `## Verification` command fails. Re-read Approach → re-read failing test → binary-search → write regression test → fix and re-run. On no-clear-cause, append to `findings.md ## Errors` and surface to the user; do NOT iterate blindly.
---

# systematic-debugging-in-phase (v0.5)

When a verify command fails inside `/super-manus:impl`, the temptation is to randomly try fixes — change a line, rerun, change another, rerun. That path produces a green bar by chance and a fragile capability. This skill enforces a different loop.

## When this skill applies

- A phase test that the test-writer committed red is still red after the code-writer claimed done.
- A `## Verification` command in `tasks/p<n>_impl.md` exited non-zero or produced wrong output.
- The orchestrator's hash check passed (i.e. tests were not tampered with) — if hashes mismatched, that's a different abort path; this skill does not apply.

## The 5-step checklist

Follow in order. Do NOT skip steps because "I think I know what's wrong".

### Step 1 — Re-read `tasks/p<n>_impl.md ## Approach`

Open the phase plan. Re-read `## Approach` end to end. Ask:

- Was an assumption in `## Approach` violated by the code that was actually written?
- Did `## Approach` mark a sub-bullet `(decide)` that the code-writer resolved silently the wrong way?
- Did the code-writer write code that contradicts a `findings.md ## Decisions` entry referenced in `## Approach`?

If any of those is true, the bug is in the plan-vs-code mismatch, NOT in the test. Fix the code to match `## Approach`. Re-run. If green, stop here.

### Step 2 — Re-read the failing phase test

Open the failing phase test file. Read it line by line. Ask:

- What user-observable claim does this test encode? (Pull it back to PRD `## What users get` / `## Quality bar` / `## Demo`.)
- Does the current implementation produce that observable?
- Is the test asserting on the right surface (HTTP body, CLI stdout, file contents) or on internal plumbing?

If the test asserts the right thing but the impl produces the wrong observable → bug is in the impl. Continue to step 3.

If the test asserts the wrong thing (encodes a contradiction with PRD, or a typo makes it un-passable in any impl) → DO NOT modify the test. Skip to the no-clear-cause path: append to `findings.md ## Errors`, surface to user, stop.

### Step 3 — Binary-search the changed lines

Use git: `git diff HEAD~1` (or the code-writer's commit range) to see exactly which lines changed in this phase. Then:

1. Comment out (or `git stash`) half of the changed lines. Re-run the failing test.
2. Pass? The bug is in the half you commented out. Restore that half, comment out half of THAT half. Re-run.
3. Fail? The bug is in the half you kept. Recurse.

Continue until the failing region is one or two lines.

For non-code failures (env, config, missing file): swap "lines" for "config knobs" and run the same bisection on the config delta.

### Step 4 — Write a regression test capturing this failure mode

Once the failing region is localised, write a new minimal test that captures the exact failure mode. Where to put it:

- If the orchestrator allows test-writer re-spawn (the failure exposed a coverage gap PRD didn't anticipate), respawn `impl-test-writer` to add the regression test under `tests/phase_p<n>_*.{ext}`.
- Otherwise, document the reproduction in `findings.md` under `## Data points / research`:
  ```
  - <date>: phase p<n> regression — exact reproduction:
    <minimal command + expected vs actual>
  ```

This is the "leave the campsite better than you found it" step. Without it, future debugging on the same module will retread the same diagnosis.

### Step 5 — Fix and re-run

Apply the smallest fix that addresses the localised failing region. Then:

1. Re-run the failing phase test. Confirm green.
2. Re-run ALL phase tests for this phase (`pytest docs/super-manus/impl/<m>/<u>/tests/phase_p<n>_*.py -v` or equivalent). Confirm all green.
3. Re-run every command in `tasks/p<n>_impl.md ## Verification` from the top. Confirm all green and every observable matches.

If step 1, 2, or 3 fails, restart this checklist from step 1 — the fix introduced a new failure mode.

## When the checklist doesn't converge — no clear cause

If you've completed all 5 steps and the test is still failing, OR step 2 surfaced a test-vs-PRD contradiction that the code-writer cannot fix:

1. Append a row to `findings.md ## Errors`:
   ```
   | <YYYY-MM-DD> | phase p<n> verify failure | tried: re-read Approach, bisected to <region>, wrote regression in <path>; symptom: <one-line>; suspect: <one-line> |
   ```
2. Surface the symptom + suspect to the user verbatim.
3. STOP. Do NOT keep iterating blindly. Do NOT try random fixes.

The 3-strike error protocol from `skills/using-sm/SKILL.md §6` applies: at most three attempts on the same error class before escalation. This checklist counts as one well-formed attempt; falling back to random tries is what the protocol forbids.

## Anti-patterns this skill exists to prevent

- "Try `time.sleep(1)`" — adding sleeps to flaky tests instead of finding the race.
- Editing the test to make it pass — explicitly forbidden by the code-writer's persona.
- Marking the test `@pytest.skip(reason="flaky")` — explicitly forbidden by `tdd-in-phases`.
- "Try a different library" — large-scale rewrites in response to a localised failure. Bisect first.
- Committing the half-fix and moving on — phase stays `in_progress` until ALL `## Verification` exits green.

## Karpathy guidelines connection

The 5-step checklist is the literal "surgical changes" + "surface assumptions" + "verifiable success criteria" practice from `andrej-karpathy-skills:karpathy-guidelines`. Bisection finds the smallest change; re-reading `## Approach` surfaces the violated assumption; re-running `## Verification` is the verifiable criterion.
