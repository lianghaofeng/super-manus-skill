# super-manus — Design Doc (v0.7)

> Current design. Adds a 4th agent (`impl-reviewer`) to the impl pipeline, driven by 3 review points with re-spawn loops and a hard escalation budget.
>
> Supersedes [docs/design-v0.6.md](design-v0.6.md) (v0.6 — `prd-update` dual-mode). Layout, hooks, end-of-update drift gate, e2e regression suite, all 3 writer agents (impl-architect / impl-test-writer / impl-code-writer), all skills (`tdd-in-phases`, `verification-before-phase-close`, `systematic-debugging-in-phase`, `using-sm`), `prd-update` dual-mode, and the slash command surface are otherwise unchanged from v0.6.

## 1. What changed from v0.6

A real dogfood case (multi-source parser phase, May 2026) exposed two structural gaps in v0.6's 3-agent pipeline:

- **Plan-time fabrication.** `impl-architect` drafted a 6-source parser plan citing field names ("cn-k12 has `id`/`problem`/`solution`", "gsm8k is `.jsonl`", etc.) that turned out to be wrong for 5/6 sources — none had been verified against real files via `head -1`. `impl-test-writer` then produced inline-dict fixtures from architect's plan, `impl-code-writer` made tests green against those fixtures, verification ran one source's smoke and passed. Phase closed green; production data dropped 5/6 sources silently.
- **Test-side dead-end.** When phase tests are wrong (un-passable, type-broken, or anchored on wrong fixtures), `impl-code-writer` is forbidden by the cheat-prevention barrier from editing tests. Today's escape hatch ("user edits the test directly, or runs `prd-update` and re-spawns test-writer") is conceptually documented in `skills/tdd-in-phases/SKILL.md` but mechanically unwired — the user has to know they can break the hash baseline by hand-editing, then somehow re-establish it on the next phase entry. No reviewer or command makes this clean.

Both gaps share a root cause: **every agent in the pipeline trusts the previous agent's output as ground truth**. Architect → test-writer → code-writer is a linear trust chain; no one in the chain has the explicit job of *checking the chain against external reality*. v0.6 v0.5 patched specific symptoms (the bb17780 commit forced phase-test path declarations; the prd-update dual-mode covered drift absorption) but the structural gap stayed.

v0.7 closes it with a **fourth agent**, `impl-reviewer`, invoked at three checkpoints inside `/super-manus:impl` (and `/super-manus:impl-all`):

```
[1] impl-architect drafts tasks/p<n>_impl.md      (writes plan)
       ↓
[2] impl-reviewer (mode=pre-test)                 (read-only)
       ├─ APPROVE → continue                      ──→ counter[#1] = 0
       ├─ RETURN_TO_ARCHITECT(<feedback>)         ──→ counter[#1] += 1; re-spawn [1] with feedback
       └─ ESCALATE_TO_USER(<reason>)              ──→ stop, surface verdict
       ↓
[3] impl-test-writer commits red tests            (writes tests)
       ↓
[4] impl-reviewer (mode=pre-code)                 (read-only)
       ├─ APPROVE → continue                      ──→ orchestrator hashes tests
       ├─ RETURN_TO_TEST_WRITER(<feedback>)       ──→ counter[#2] += 1; re-spawn [3]
       ├─ RETURN_TO_ARCHITECT(<feedback>)         ──→ counter[#2] += 1; re-spawn [1] then [3]
       └─ ESCALATE_TO_USER(<reason>)              ──→ stop
       ↓
[5] impl-code-writer commits source until green   (writes code)
       ↓
[6] impl-reviewer (mode=pre-close)                (read-only)
       ├─ APPROVE → continue                      ──→ orchestrator runs ## Verification
       ├─ RETURN_TO_CODE_WRITER(<feedback>)       ──→ counter[#3] += 1; re-spawn [5]
       ├─ RETURN_TO_TEST_WRITER(<feedback>)       ──→ counter[#3] += 1; re-spawn [3] then [5]
       ├─ RETURN_TO_ARCHITECT(<feedback>)         ──→ counter[#3] += 1; re-spawn [1] then [3] then [5]
       └─ ESCALATE_TO_USER(<reason>)              ──→ stop
       ↓
[7] orchestrator hash check + ## Verification + close
```

**Reviewer is the loop driver.** Writers stay stateless — they don't know they're on attempt N; they just read `previous_attempt_feedback` from their spawning prompt (a new optional input) and address each item.

## 2. The reviewer agent

### Role

`impl-reviewer` is the only agent in the pipeline whose explicit job is to **check the chain against external reality**. Its persona:

> Senior staff engineer (15 years), one role: catch the things the writers couldn't catch about themselves. You read everyone else's output. You write nothing. You produce one of three verdicts. Your default is to RETURN, not APPROVE — APPROVE is earned, not given.

### Tools

`Read, Glob, Grep, Bash` — **no `Write`, no `Edit`**. Read-only by tool surface, not just by persona. Reviewer cannot accidentally mutate plan / tests / code / state files.

### Modes

The reviewer file `agents/impl-reviewer.md` defines a single agent with three invocation modes selected via a `mode` input from the orchestrator:

#### Mode `pre-test` (after architect, before test-writer)

Reviewer reads `tasks/p<n>_impl.md`, the module PRD, and a sample of any external inputs the plan declares. Checks:

- **Real-data grounding.** For each external input the plan declares (file format, schema, third-party API shape), reviewer runs `head -1 <file>` / `jq '.[0]'` / `od -c` / equivalent and **compares quoted bytes against plan claims**. Plan must either include a real-data sample in `## Approach` (preferred) or have its claims be verifiable by a quick sample. If schema in plan disagrees with bytes on disk → `RETURN_TO_ARCHITECT`.
- **`(audit)` markers resolved.** Any unresolved `(audit)` marker in `## Files touched` or `## Approach` blocks APPROVE. Architect must either resolve it (verify and concretize) or punt it explicitly to PRD `## Open questions`. No "I'm unsure but moving on".
- **`## Verification` covers all declared inputs.** If the plan claims to support N input sources, `## Verification` must include at least one smoke per source (a `for source in $sources; do ... done` loop counts).
- **Karpathy guideline check** (`using-sm/SKILL.md §9`): surgical / surface assumptions / verifiable / no overcomplication.

#### Mode `pre-code` (after test-writer, before code-writer)

Reviewer reads the tests just committed, plus plan, plus PRD. Checks:

- **Real-data fixtures for IO/parser/serializer code.** If the plan touches a parser/loader/wire-format/schema-converter, reviewer verifies that fixtures come from real files (not inline dicts derived from plan text). At least one fixture per declared source must be a literal record from the source.
- **Coverage of declared inputs.** If plan declares N sources, tests must include at least one assertion per source.
- **No mirror-test reflex** (already in `tdd-in-phases`): tests must not import private helpers named in `## Approach`, must not assert on internal state, must not have expected values shaped like the impl's would-be return.
- **Tests are red as expected.** Reviewer runs the phase test command once; if any test passes already, that's a `RETURN_TO_TEST_WRITER` ("test is vacuous — passes before code is written").
- **Type-check / lint clean** (when project config exists). If `pyproject.toml` declares mypy/pyright, or `tsconfig.json` declares strict mode, reviewer runs the type-checker on the test files. Errors → `RETURN_TO_TEST_WRITER` with the specific lines. (Project doesn't configure type-check → skip this check; not in scope to impose.)

#### Mode `pre-close` (after code-writer reports green, before orchestrator runs `## Verification`)

Reviewer reads the source diff, plus tests, plus plan. Checks:

- **Implementation matches `## Approach`.** Code-writer didn't drift toward a different design.
- **Karpathy: surgical changes.** No unrelated refactors, no "while I was here" cleanup, no abstraction introduced for single-use code.
- **Touched files are subset of `## Files touched`.** If code-writer modified files not declared in plan, that's a `RETURN_TO_CODE_WRITER` (or, if reviewer thinks the plan was actually too narrow, `RETURN_TO_ARCHITECT`).
- **Code-writer "stuck" handling.** If code-writer returned with "tests un-passable" rather than green, reviewer reads the failing tests and decides: is this code-writer's failure (RETURN_TO_CODE_WRITER, "try with hint X"), test-writer's failure (`RETURN_TO_TEST_WRITER` with feedback "fixture for X is wrong; real shape is Y"), or architect's failure (`RETURN_TO_ARCHITECT`, "plan §3 said `x.strip()` but x is a list per real data")?
- **Security / secrets smell.** No hardcoded credentials, no `eval()` on user input, no obvious SQL injection.

### Verdict format

The reviewer returns one of:

```
APPROVE
  ↓
  Single line: "Reviewed pre-<mode> for phase p<n>; <one-sentence summary of why approved>."

RETURN_TO_<writer>
  ↓
  Multi-line structured feedback:
    target: ARCHITECT | TEST_WRITER | CODE_WRITER
    issues:
      - <one concrete issue, with file/line if applicable>
      - <another>
    suggested_actions:
      - <what the re-spawn writer should do specifically>
    why_not_escalate: <one sentence — why this is fixable by re-spawn, not by user intervention>

ESCALATE_TO_USER
  ↓
  Multi-line:
    reason: <one sentence — why the loop can't converge>
    history: <each prior RETURN at this review point with its feedback>
    user_options:
      - <option A — typically a writer-side fix the user could guide>
      - <option B — typically a plan or PRD edit>
      - <option C — typically "abort phase" or "edit tests directly per pre-v0.7 escape hatch">
```

### Read priority

```
[primary]   tasks/p<n>_impl.md (full)            — what the architect committed to
[primary]   prd/<module>.md + prd/_index.md      — what user-visible truth the phase serves
[primary]   the immediate previous writer's output (plan / tests / code diff)
[secondary] head -1 (and similar) of each external input declared in plan
[secondary] findings.md ## Errors                — prior reviewer feedback, to avoid repeating
[secondary] phase tests + e2e tests              — to know what code is being asked to do
[context]   source code via LSP / grep            — only enough to verify claims
```

### Budget

```
LSP: ≤5 calls per review (workspace_symbols / document_symbols / find_references)
grep / Read: ≤15 calls per review
external-data probes (head, jq, od, curl): ≤10 per review
```

Tighter than the writers because reviewer's job is verification, not exploration. Over-budget → ESCALATE_TO_USER with "couldn't converge within budget".

## 3. Re-spawn protocol

When the reviewer issues `RETURN_TO_<writer>`, the orchestrator does the following:

1. **Increment the per-review-point counter.** Counter belongs to the review point that issued the RETURN, not to the writer being re-spawned. So `RETURN_TO_ARCHITECT` from review #3 increments `counter[#3]`, even though architect is upstream.
2. **Check budget.** If `counter[#<review-point>] > 2`, do not re-spawn. Instead: append all prior feedback to `findings.md ## Errors`, surface the full history to the user as ESCALATION (same shape as `ESCALATE_TO_USER`), and stop. Phase status stays `in_progress`; user resolves.
3. **Re-spawn target writer with feedback.** The orchestrator re-invokes the target subagent (`Agent` tool, same `subagent_type`) with the same inputs as before, plus a new `previous_attempt_feedback` field containing the reviewer's issues + suggested_actions verbatim. The writer's prompt skeleton gets one extra block:

   ```
   > previous_attempt_feedback (reviewer rejected your previous output):
   > <issues, multi-line>
   > suggested_actions: <multi-line>
   >
   > Address each issue. If you believe an issue is wrong, say so explicitly in your summary line — do not silently ignore.
   ```

4. **Cascade re-spawns when target is upstream.** If review #3 returns to architect, the chain after architect's re-spawn must replay: architect → test-writer → code-writer → review #3. The intermediate reviewers (#1, #2) re-run as well — they're cheap and cheap insurance. Counters at #1 and #2 reset for the new attempt (since plan / tests are fresh); counter at #3 stays incremented.
5. **Hash baseline refresh.** If test-writer is re-spawned (whether from review #2 or as part of a deeper cascade), its new commit produces new test files; orchestrator re-hashes after the new test commit and before code-writer is re-spawned. The cheat-prevention boundary is preserved because the hash baseline always reflects the latest test commit at the moment code-writer is spawned.

### Counter rules summary

| Review point | Possible RETURN targets | Counter incremented on RETURN |
|---|---|---|
| #1 (pre-test) | ARCHITECT | counter[#1] |
| #2 (pre-code) | TEST_WRITER, ARCHITECT | counter[#2] |
| #3 (pre-close) | CODE_WRITER, TEST_WRITER, ARCHITECT | counter[#3] |

Each counter is independent. ESCALATE happens when any single counter exceeds 2.

### Why per-review-point counters (not per-writer counters)

The bug is at the *checkpoint*, not at the *writer*. If review #3 keeps rejecting code-writer's output, the issue is not "code-writer is dumb" — it's "review #3 has a standard the system can't meet". Escalating to user when a *checkpoint* is stuck gives the user the right diagnostic information: "the pre-close review keeps finding issues, you need to look at it".

If reviewer routes to architect from #3, that's still a #3-checkpoint problem (review #3 thinks the plan is wrong). Counting against #3 captures that.

## 4. Cheat-prevention preservation

The reviewer does not weaken the v0.5 hash-based cheat-prevention. Three reasons:

- **Reviewer is read-only by tool surface.** It cannot edit tests, code, or plan. The hash baseline is unaffected by reviewer's actions.
- **Test re-spawn re-establishes baseline cleanly.** When test-writer is re-spawned, it commits new tests; orchestrator re-hashes the new commit. Code-writer is then spawned with the new baseline. No window in which code-writer sees the old baseline + new tests.
- **Reviewer cannot bypass the hash check.** The post-code hash check (Step 4 in v0.6's `commands/impl.md`) still runs after code-writer returns and before phase close. If code-writer somehow modified tests, the hash mismatch fires regardless of what reviewer said at pre-close.

The reviewer adds a **second class** of barrier (correctness, not cheat-prevention) on top of the existing first class. They compose; they don't conflict.

## 5. Q2 escape hatch — what happens to it

The pre-v0.7 escape hatch in `skills/tdd-in-phases/SKILL.md ## What code-writer must NOT do`:

> If a test is genuinely wrong (encodes a contradiction with PRD, has a typo that makes it un-passable in any impl), the code-writer MUST stop, append a row to `findings.md ## Errors` describing the contradiction, and surface to the user. The user resolves — either by editing the test directly, or by editing PRD (via `/super-manus:prd-update`) and re-spawning `impl-test-writer`.

Becomes mostly automated in v0.7:

- Code-writer still stops and writes to `findings.md ## Errors` when stuck.
- But the orchestrator no longer surfaces this directly to the user. Instead, it spawns `impl-reviewer` in `pre-close` mode with the stuck state.
- Reviewer reads the failing test + the code-writer's attempted impl + the plan + the PRD. Decides:
  - Test is wrong → `RETURN_TO_TEST_WRITER` with specific feedback ("fixture for X uses inline dict; real data shape is Y per `head -1 <file>`").
  - Plan is wrong → `RETURN_TO_ARCHITECT` with feedback.
  - Code-writer just gave up too early → `RETURN_TO_CODE_WRITER` with hint.
  - None of the above (genuinely contradictory PRD, scope ambiguity) → `ESCALATE_TO_USER` with the same options the v0.6 escape hatch listed (edit test directly / `prd-update` / abort).

The user-facing escape hatch (edit test directly with hash break) stays documented as a **last resort** option inside ESCALATE_TO_USER's `user_options` block. It's no longer the primary path because reviewer handles the common cases automatically.

## 6. Slash command surface (v0.7 — unchanged from v0.6)

| Command | Role | Changed in v0.7? |
| --- | --- | --- |
| `/super-manus:start` | (no args) idempotent enable | no |
| `/super-manus:brainstorm` | 6-question Q&A, initial PRD | no |
| `/super-manus:reverse-prd` | one-shot scan of existing project | no |
| `/super-manus:sync <module>` | PRD-diff → Phases → scaffold update | no |
| **`/super-manus:impl`** | **one phase via 4-agent pipeline (was 3-agent)** | **yes — adds reviewer at 3 review points; same outward shape** |
| **`/super-manus:impl-all`** | **loop all pending phases via 4-agent pipeline** | **yes — same as impl, looped** |
| `/super-manus:prd-update <module>` | structured PRD edit (forward OR drift) | no |
| `/super-manus:drive` | global next-step decider | no |
| `/super-manus:catchup` | re-inject context | no |
| `/super-manus:log` | manual session log | no |

User invocation does not change. From outside, `/super-manus:impl` still means "ship one phase end-to-end". Internal pipeline is now 4 agents, but that's an implementation detail — the slash command's contract is preserved.

## 7. Migration from v0.6

Pure additive. No path changes, no schema changes, no data migrations. v0.6 projects gain reviewer enforcement automatically the next time `/super-manus:impl` runs. Existing on-disk state (PRD, roadmap, drift log, impl folders, e2e tests) requires no edits.

Files added:

- `agents/impl-reviewer.md`
- `tests/test_agent_impl_reviewer.sh`

Files modified:

- `commands/impl.md` — orchestrator inserts 3 review steps with retry / escalate logic.
- `commands/impl-all.md` — same review logic per phase.
- `skills/tdd-in-phases/SKILL.md` — `## The non-negotiable order` updated from 6 steps to 8 (review steps inserted).
- `agents/impl-architect.md` / `agents/impl-test-writer.md` / `agents/impl-code-writer.md` — each gets a `## Receiving reviewer feedback` section explaining how to consume `previous_attempt_feedback` on re-spawn.
- `tests/test_skill_tdd_in_phases.sh` / `tests/test_command_impl_logic.sh` / `tests/test_command_impl_all_logic.sh` — assertions updated for new step count and new agent.
- `README.md` / `README.zh-CN.md` — `## Self-sufficient execution discipline` mentions reviewer + 4-agent pipeline; `## Updates` gains v0.7 entry.

The v0.6 invariants still hold:

- 9 H2 sections in `prd/<module>.md`, 8 H2 sections in `prd/_index.md`.
- 4 H2 sections in `phase_plan.md`.
- e2e at `docs/super-manus/e2e/<module>/test_<capability>.<ext>` and `_system/test_<scenario>.<ext>`.
- Hash-based cheat-prevention between test-writer and code-writer.
- Append-only `prd_drift.md` with mutable Resolution column.
- End-of-update gate's 3 passes (refresh / e2e coverage / pending == 0).

## 8. Out of scope (v0.7)

Deferred or rejected:

- **Reviewer for non-impl commands** (e.g. brainstorm, sync, prd-update). These commands already have user-as-reviewer in the loop (the user audits the output before proceeding). Adding a reviewer here would add latency without clear benefit.
- **Per-writer counter** (instead of per-review-point). Considered and rejected in §3 — per-checkpoint is the right diagnostic granularity.
- **User-tunable retry budget.** Hardcoded at 2. Adding a config knob now is premature; collect data first.
- **Reviewer asking the user mid-flight.** Reviewer's only escape valve is `ESCALATE_TO_USER` at the end of its run. No interactive Q&A — that would fragment the loop and require state.
- **Reviewer re-spawning itself.** No self-loops. If reviewer's own analysis is bad, the user catches it via the per-checkpoint counter exhaustion.
- **Cross-phase reviewer state.** Reviewer is invoked fresh each phase, with no memory of prior phases. (Future: maybe surface "reviewer rejected phase p<n-1> 2 times for similar reasons" as a hint.)
- **`/super-manus:test-rebaseline`** (the alternative considered in the design discussion). Replaced by reviewer's automatic `RETURN_TO_TEST_WRITER` path. Manual hand-edit-then-rebaseline stays as the last-resort option inside ESCALATE_TO_USER's user_options.
- Everything still out of scope per [design-v0.6.md §6](design-v0.6.md) and [design-v0.5.md §10](design-v0.5.md).

## 9. Plugin version

v0.7.0 (additive vs v0.6: reviewer agent + 3 review points + re-spawn loop; no path migration, no PRD-schema changes, no test-fixture changes). Plugin manifest at `.claude-plugin/plugin.json` is the canonical version source.

## 10. Decisions (resolved during audit)

These choices were made during user audit before implementation. All five locked.

1. **Retry budget = 2** (3 attempts total per checkpoint: original + 2 re-spawns). Reasoning: 2 gives the writer room to incorporate two rounds of feedback without dragging the loop into infinite-retry territory; 3 was considered too forgiving and would mask checkpoint-side problems (a checkpoint stuck for 4 rounds is a checkpoint problem, not a writer problem).
2. **No pre-architect review point.** Reviewer runs at three points only — pre-test, pre-code, pre-close. Adding a fourth checkpoint before architect is spawned was considered and deferred: the user already audits `task_plan.md ## Phases` before invoking `/super-manus:impl`, so user-as-reviewer covers the slot. Cheap to add later if data justifies.
3. **Pre-test reviewer runs `head -1` itself** (rather than relying on architect to paste real-data samples into `## Approach`). Reasoning: putting the verification step inside the reviewer keeps a single source of ground truth; relying on architect to produce samples means architect could still paste paraphrased / outdated content. Reviewer's tool surface includes Bash for exactly this.
4. **Type-check / lint is project-configured-only** ("pure A"). If `pyproject.toml` declares mypy/pyright, or `tsconfig.json` declares strict mode, the pre-code reviewer runs that checker on the test files. **If the project has no such config, the reviewer skips type-check entirely.** No fallback `python -m py_compile` floor check, no forced strict checker. Reasoning: super-manus should respect project conventions, not impose strict typing on projects that intentionally use untyped code. The dogfood case (pyright `Iterator[str]` error) would be caught here because that project does configure pyright.
5. **Reviewer references `using-sm/SKILL.md §9`** (the four karpathy-guidelines principles: surgical / surface assumptions / verifiable / no overcomplication) as its coding-discipline touchstone, same as the writers. No reviewer-specific checklist for now. Flagged for future maintainers if specialization proves necessary.
