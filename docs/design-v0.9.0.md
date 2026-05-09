# super-manus v0.9.0 — reviewer upgrade: edge-case discipline + corroborated test runs

## 1. What changed from v0.8.4

Three reviewer-upgrade changes (called A, C, D in the design discussion that produced this version) plus the structural template change that D requires.

- **A — pre-close reviewer runs phase tests + touched e2e tests itself.** Code-writer's "all green" self-report is corroborated, never assumed. False-green-claim → `RETURN_TO_CODE_WRITER`.
- **C — pre-close budget bumped grep/Read 15 → 25.** Was tight to the point of forced ESCALATE on medium projects; A and D both push the realistic floor up.
- **D — `phase_plan.md` gains a 5th H2 section: `## Edge cases`.** Architect commits to a 3–5-bullet checklist anchored in PRD `## Quality bar` / `## Risks` (or named failure modes). Reviewer pre-test rejects vague / unanchored bullets. Reviewer pre-code requires every non-`(audit)`, non-scaffolding bullet to be covered by ≥1 test assertion.

A and C are surgical reviewer changes. D is structural — it breaks the 4-section phase-plan invariant that has held since v0.5. **Per-update plans drafted before v0.9.0 ship continue to work via an in-place migration path** (see §5).

What v0.9.0 is **not**:

- No new agent. No fan-out reviewer. No security scanner integration. No performance benchmark. The reviewer stays a single Opus call with read-only tool surface.
- No "design quality" / "architecture critique" pass. That category was rejected during the design discussion as fundamentally unreliable to do via single-LLM judgment without falsifiable grounding.
- No multi-reviewer voting. Same reason.

## 2. Why these three, and why now

The v0.8 reviewer is a "trust-chain bookkeeper": architect → test-writer → code-writer is a linear-trust pipeline, and the reviewer at three checkpoints catches mechanical propagation errors (plan miscopied schema, test fixture diverges from real data, code touched files outside scope). It does that part well.

The honest blind spot: **test depth**. Pre-code's "plan declares N sources → tests have ≥N assertions" is a *forgetfulness* check, not a *shallowness* check. It catches "test-writer skipped a whole data source"; it does not catch "test-writer only covered the happy path while PRD `## Quality bar` calls out empty-input behavior". The escape hatch in v0.8 was "the architect should specify edge cases in `## Approach`" — but `## Approach` is engineering voice (function names, module boundaries), and there is no normative requirement that it enumerate edge cases. In practice, no architect did, and the reviewer had nothing to check against.

D is the surgical fix: lift edge-case enumeration from "implicit, hoped-for" to "an architect-committed, reviewer-checkable checklist". The architect now has a section it must fill, and the reviewer has a list it can walk against the test diff. This is a *mechanical* coverage check (does test X exist for bullet Y?) — not a *taste* check (is this test deep enough?). Mechanical checks are the only kind super-manus has decided to do reliably.

A closes a related blind spot, narrower in scope: **the reviewer trusted code-writer's self-report on green status**. The orchestrator runs `## Verification` after pre-close APPROVE, but pre-close's APPROVE was already given before any third-party verification. That is, code-writer says "green", reviewer asks "does the diff look surgical?" (yes), reviewer APPROVEs. If code-writer lied or got the run wrong, reviewer never noticed. v0.9.0 makes the corroboration explicit: pre-close runs the tests itself, exactly once. False-green-claim becomes a recognized RETURN reason.

C is the budget bump A and D require. Walking edge-case bullets and running tests both consume Bash + Read calls. The old budget of 15 grep/Read was tight even for v0.8 medium projects (diff + touched files + plan + PRD). Bumping to 25 is the smallest increment that doesn't create new ESCALATE-without-converging cases.

## 3. The structural change in detail

### 3.1 phase_plan.md — 5 H2 sections (was 4)

```
## Objective
## Approach
## Edge cases       ← NEW in v0.9.0
## Files touched
## Verification
```

Section position is load-bearing: `## Edge cases` MUST sit between `## Approach` and `## Files touched`. The architect's legacy-migration logic (insert in place between those two anchors) depends on this position; downstream parsers do too. `tests/test_template_phase_plan.sh` enforces ordering via `awk`.

### 3.2 Edge cases content rules

- **3–5 bullets minimum** — not zero, not one, not "TBD". Reviewer pre-test RETURNs on anything else.
- **One single-bullet exception**: `Pure happy-path scaffolding; no edge case enumeration possible at this phase. (Reviewer may RETURN if it disagrees.)` — for trivial phases (DI wiring, empty file scaffolding). Reviewer can challenge this exception with a plausible counter-example.
- **Each bullet is concrete + testable.** Vague labels (`error_handling: yes`, `input validation`, `edge cases will be considered`) → RETURN.
- **Each bullet is anchored.** Trace required to one of:
  - PRD `## Quality bar` clause
  - PRD `## Risks` clause
  - A specific named failure mode (for tech-internal phases)
- **`(audit)` markers allowed** for cases the architect suspects but can't confirm without coding. Same policy as `## Files touched`: must be resolved before pre-test APPROVE.

### 3.3 Reviewer checks

**pre-test (after architect, before test-writer):**

New check #4 walks `## Edge cases` and verifies enumeration count, concreteness, and anchoring. Karpathy guidelines moved to check #5.

**pre-code (after test-writer, before code-writer):**

New check #3 walks each non-`(audit)`, non-scaffolding `## Edge cases` bullet and locates the test file + line(s) that exercise it. Coverage must be **explicit** — no "covered implicitly". Existing checks renumbered 4–8.

**pre-close (after code-writer, before orchestrator runs ## Verification):**

New check #6 runs phase tests + touched e2e tests via Bash. ONCE. The "do not iterate" rule from `## What you do NOT do` is preserved — what changes is that the run happens at all (was implicit-or-skipped, now explicit-and-required). False-green-claim (code-writer reported green, reviewer's run is red) → `RETURN_TO_CODE_WRITER` with that verdict tag.

### 3.4 Budget

```
LSP calls:                     ≤5 per review     (unchanged)
grep / Read calls:             ≤25 per review    (was ≤15)
external-data probes:          ≤10 per review    (unchanged)
type-check tool invocations:   ≤2 per review     (unchanged)
phase-test / e2e-test runs:    1 per phase test command + 1 per touched e2e file (NEW; pre-close only)
```

## 4. Migration

### 4.1 Fresh phases (no migration required)

Any phase plan drafted on v0.9.0 onward seeds from the new template. All five sections present. No special handling.

### 4.2 In-flight phases with a 4-section plan

When `impl-architect` is spawned and finds a `tasks/p<n>_impl.md` with substantive `## Objective` / `## Approach` / `## Files touched` / `## Verification` but no `## Edge cases`:

1. Idempotency does NOT trigger (the plan is incomplete by v0.9.0 standards).
2. Architect uses `Edit` to insert a `## Edge cases` section between `## Approach` and `## Files touched`.
3. All other content is preserved verbatim.
4. Architect returns `migrated legacy plan; added Edge cases section`.
5. The orchestrator surfaces the migration to the user before the next review checkpoint, so the user can sanity-check the inserted edges before tests are written.

This is the only migration path. There is no batch script — migration is per-phase, lazy, on the next architect spawn.

### 4.3 Closed phases (immutable)

Closed phases under `docs/super-manus/impl/<module>/<update>/tasks/` are historical record and are NOT migrated. Their 4-section shape is the v0.8.x archive; leave as-is.

## 5. What v0.9.0 does NOT do — and why

These were considered and rejected in the design discussion that produced this version. Recording them here so the rejection is not relitigated without new evidence.

- **Architecture / design-quality review.** Single-LLM "is this design good?" produces unfalsifiable verdicts. Either the user starts auto-approving (rubber stamp) or auto-disregarding (reviewer becomes a moot pass). Both worse than absence.
- **Deep security audit.** The current 5-bullet smell list (hardcoded creds / `eval` / SQL concat / disabled TLS) is preserved as a *floor*, not the upgrade path. Real authz/input-validation/deserialization audits require human or specialized-tool grounding the reviewer doesn't have. Documented as user-owned at commit-review time.
- **Performance regression detection.** No automated path that works without a benchmark suite the project committed to. Stays user-owned.
- **Multi-reviewer fan-out.** Cost ~5×; the rejected blind spots (taste, deep security, perf) don't get fixed by majority vote of the same blind LLM.
- **Mutation testing integration.** Considered for "test depth" — rejected as too project-specific to ship default-on. Future opt-in path possible if a real project surfaces the need.

The path forward IS deferred, not denied: a v1.0.0 fan-out architecture (opt-in sub-reviewers per project config, mirroring the current type-check opt-in pattern) is plausible. v0.9.0 deliberately stays single-reviewer to keep the surgical change small and verifiable.

## 6. Files touched

```
templates/phase_plan.md                # +## Edge cases section between Approach and Files touched
agents/impl-architect.md               # 5-section procedure, edge case discipline, legacy migration
agents/impl-reviewer.md                # pre-test edge-case check, pre-code coverage walk, pre-close test run, budget bump
commands/impl.md                       # 5-section verification, seed mention
skills/using-sm/SKILL.md               # sections list (4 → 5)
CLAUDE.md                              # template invariants (4 → 5 H2)
tests/test_template_phase_plan.sh      # ## Edge cases assertion + ordering
tests/test_agent_impl_architect.sh     # 5-section + edge case discipline + legacy migration
tests/test_agent_impl_reviewer.sh      # budget bump (15→25) + edge case checks + pre-close test-run check
docs/design-v0.9.0.md                  # this file
.claude-plugin/plugin.json             # version 0.8.4 → 0.9.0
.claude-plugin/marketplace.json        # version 0.8.4 → 0.9.0
```

## 7. Tests

`tests/run-all.sh` continues to pass with the updated assertions. No test was deleted or weakened — every v0.9.0 test addition is additive on top of v0.8.x discipline. The five-section template is enforced both at the template level (`test_template_phase_plan.sh`) and at the agent level (`test_agent_impl_architect.sh`); the reviewer's new behaviors are enforced in `test_agent_impl_reviewer.sh`.

## 8. Known limitations & open questions

The cross-validation audit run on v0.9.0 (three independent reviewer agents) surfaced three known limitations the surgical release does NOT solve. They are recorded here so the next contributor doesn't re-discover them and so v1.0.0 design starts from this floor.

### C1 — Ritualized-but-useless edge bullets (real, unaddressed)

**Manifestation.** Architect fills `## Edge cases` with shape-compliant but semantically empty bullets, e.g.:

```
- Empty input — anchored in PRD ## Quality bar "be robust"
```

The bullet IS anchored (cites a real `## Quality bar` clause), IS concrete-input-shape-named ("Empty input"), passes reviewer pre-test enumeration check. But "be robust" gives the test-writer no behavior to assert — they either invent a behavior (becoming de facto spec author, which v0.9.0 explicitly tries to prevent) or write a tautology like `assert run([]) is not None`, which then passes pre-code coverage check #3 because a test exists with the matching name.

**Why v0.9.0 doesn't fix it.** The mechanical fix is to require the architect to enumerate **which exact PRD clause text** each bullet addresses, then have the reviewer mechanically pin bullet → clause → assertion-target chain. That requires:
1. PRD `## Quality bar` clauses to be specific enough to drive assertions (most aren't today).
2. A new plan field listing the verbatim PRD clause text per bullet.
3. Reviewer logic to parse the clause and verify the test asserts on the named behavior.

That's a v1.0.0-shaped intervention (touches PRD authoring discipline + plan template + reviewer + test-writer). v0.9.0 is surgical; it lifts enumeration from implicit to architect-committed, but stops short of mechanical clause-pinning.

**Mitigation today.** User reviews `## Edge cases` at plan-approve time; if a bullet looks ritual, push back before tests are written. The reviewer's `(audit)` escalation in the test-writer (`bullet too vague to test`) surfaces some of these — but only when test-writer notices, which is unreliable.

### C2 — Pre-close test-run wall-clock cost is unbounded (real, unaddressed)

**Manifestation.** Pre-close check #6 runs phase tests + every touched e2e file, ONCE. There is no time ceiling in the budget table — only a per-invocation count. A project with a 3-minute e2e suite pays 3 minutes per pre-close review; with retry budget 2, that's potentially 9 minutes of pure reviewer wait per phase, with no progress indicator.

**Why v0.9.0 doesn't fix it.** Adding a wall-clock escape hatch (e.g. "skip if e2e exceeds X seconds, surface as `(test-run-skipped: too slow)` non-blocking note") is a NEW design decision — what's the threshold? Per-project override? Falls back to what? The right shape isn't obvious without seeing real-project usage data. Adding an ad-hoc threshold without that data risks false negatives (slow-but-real failures get skipped).

**Mitigation today.** The orchestrator's overall ESCALATE_TO_USER path catches budget-exhaustion. Users on slow-test-suite projects will notice the latency and can either (a) speed up their e2e via parallelization, (b) accept the latency, or (c) configure `.super-manus/agents.yml` to use a faster model for impl-reviewer (cheaper-but-faster review may converge in fewer retries).

### C3 — Mid-update plugin upgrade race with hash baseline (rare, unaddressed)

**Manifestation.** A user has an in-flight phase from v0.8.4 with phase tests already committed (4-section plan, no `## Edge cases`). They upgrade the plugin to v0.9.0 mid-update. Next `/super-manus:impl` resume:
1. Architect re-spawns, detects 4-section plan, inserts `## Edge cases` (migration succeeds).
2. Orchestrator resumes the phase. If resume lands at pre-code (because the test-writer step already ran in the old version), pre-code check #3 walks the freshly-inserted `## Edge cases` and demands per-bullet test coverage.
3. The existing test commit was hashed for cheat-prevention before v0.9.0 shipped. Test-writer re-spawn rewrites tests, but the hash baseline mismatch may abort the phase.

**Why v0.9.0 doesn't fix it.** Adding a resume-state guard ("on legacy migration, re-enter at pre-test, not at the cached resume point") requires the orchestrator to track plan-shape-version per phase, which is new state. The race is also rare in practice (plugin upgrade mid-update is uncommon).

**Mitigation today.** Document the failure mode here. If a user hits it, the workaround is to abort the current phase (`task_plan.md` row → `pending`), let architect re-draft fresh, let test-writer re-write fresh. One lost phase of work; not data loss. v1.0.0 may add resume-state versioning.

### Open questions for v1.0.0

- Mechanical PRD clause pinning (fixes C1).
- Wall-clock ceiling for pre-close test runs with project-configurable threshold (fixes C2).
- Resume-state versioning + automatic re-entry-at-pre-test on legacy migration (fixes C3).
- Opt-in sub-reviewer fan-out (the architectural ceiling discussed during v0.9.0 design — security / perf / coverage sub-reviewers each with their own external tool grounding). Mirrors the existing type-check opt-in pattern.
