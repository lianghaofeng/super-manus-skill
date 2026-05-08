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

## 11. v0.7.1 addendum — PRD-template refinements

Borrowed from a formal-PRD framework discussion (DDD-flavored): two surgical edits to the PRD templates that make module boundaries semantically auditable from the PRD alone, without changing headings, MODULE–DIAGRAM INVARIANT, or any orchestrator/agent wiring beyond `agents/reverse-prd-architect.md`.

### What changed

1. **`templates/prd_module.md ## How it connects`** — section now opens with an `Exposes:` / `Consumes:` semantic preamble before the existing Upstream/Downstream/Third-party + edge list block:

   ```
   Exposes:
   - <capability name in PM voice> → <consumer module / external actor>

   Consumes:
   - <capability name in PM voice> ← <provider module / external system>

   Upstream (who calls in): ...
   Downstream (where outputs go): ...
   Third-party (external): ...

   Edge list:
   - in:  ← <X> via <protocol>
   - out: → <Y> via <protocol>
   ```

   Items are **PM-voice capability nouns** ("order placement", "credit-score lookup", "vector search"), NOT endpoint paths or symbol names. Endpoint detail stays in the Edge list where it always was.

2. **`templates/prd_index.md ## Data flow overview`** — edge list backup format gains a `(for: <capability>)` purpose annotation per edge:

   ```
   <A> --<protocol>--> <B> [path/topic] (for: <capability>)
   ```

   The capability name in `(for: ...)` matches the consuming module's `Exposes` (or its own `## What users get` bullet that the edge backs). The two sections now share one capability vocabulary.

### Why

- **Module-split decisions become auditable from PRD alone.** Before v0.7.1, the only way to evaluate "should X be its own module?" was to read `## How it connects` + edge list + count protocols. After v0.7.1, you read the Exposes block: a module exposing 12 unrelated capabilities is over-scoped; a module exposing 1 capability that's only consumed once may be premature.
- **Cross-module debugging and review get semantic context.** "Edge X carries capability Y" is meaningfully more useful than "Edge X uses gRPC" when triaging incidents or auditing scope creep.
- **Cheap to adopt incrementally.** Existing PRDs render fine without the new fields; `/super-manus:reverse-prd` re-runs fill them, manual updates work too.

### Why **not** more from the formal-PRD framework

The framework also recommended document control / changelog markers, formal NFR SLAs, rollout/rollback plans, state machines, and per-section acceptance criteria. All deliberately rejected:

- **Document control / changelog**: contradicts super-manus's "PRD is target state, `git log -p prd/<module>.md` is the audit trail" invariant. Adding dated revision marks creates rot.
- **Formal NFRs (QPS / latency SLAs)**: super-manus's `## Quality bar` already supports measurable bullets. Forcing numbers in the template pushes toward fabricated SLAs for projects that don't actually have them.
- **State machines, rollback plans, monitoring**: belong in `impl/<m>/<u>/tasks/p<n>_impl.md ## Approach` (state machines) or runbooks/SRE docs (rollback, monitoring). Not PRD scope.
- **Phased milestones inside PRD**: phasing already lives in `impl/<m>/<u>/task_plan.md ## Phases`. Duplicating it inside PRD creates a synchronization burden with no benefit.

### Cascade implemented

- `templates/prd_module.md` — new placeholder body for `## How it connects`.
- `templates/prd_index.md` — new placeholder body for `## Data flow overview` edge list spec.
- `agents/reverse-prd-architect.md` — derivation rules for both new fields:
  - **Exposes** is derived from THIS module's `## What users get` capabilities × `find-references` on the module's exports.
  - **Consumes** is derived from upstream module's `## What users get` capabilities (read directly from the upstream `prd/<upstream>.md`).
  - **`(for: <capability>)`** is derived from the consumed-side module's `## What users get` bullet that the edge backs; if no single bullet fits, mark `(for: (audit))`.
- `skills/using-sm/SKILL.md` summary line — updated to mention "Exposes/Consumes semantic preamble" alongside the structural edge list.
- `commands/prd-update.md` — added verification guidance for capability-boundary edits (Tighten/Split on Exposes/Consumes lines verifies the capability still crosses the boundary; Demote rarely applies; the `(for: <capability>)` annotation must continue to match a real upstream `## What users get` bullet).
- `tests/test_template_prd_module.sh` / `tests/test_template_prd_index.sh` / `tests/test_agent_reverse_prd_architect.sh` — keyword assertions for `Exposes:`, `Consumes:`, `(for:`.

### Migration

None required. Existing PRDs render fine — headings are unchanged, all parsers continue to work, tests stay green. To adopt the new fields:

- **New PRDs** created via `/super-manus:start` followed by `/super-manus:brainstorm` or `/super-manus:reverse-prd` get the new fields automatically.
- **PRDs that ran reverse-prd once but were not yet human-audited** (`## Problem` still placeholder / `(audit ...)`) — re-run `/super-manus:reverse-prd` (whole-project) without confirmation. Cost ≈ original reverse-prd cost (full Stage 1 + per-module LSP + writes); not delta-only.
- **PRDs that have been human-audited** (real content in `## Problem`) — three options ordered cheap → expensive:
  1. (v0.7.2) Run `/super-manus:reverse-prd <module>` per module to refresh just that one module's `prd/<module>.md` with the new fields. Per-module mode skips `_index.md` and other modules; cascade-scan reports which other modules might be stale.
  2. Edit by hand. Each module typically needs 2–5 Exposes/Consumes lines — a human who knows the project produces more accurate capability names than the architect's inference anyway.
  3. Run `/super-manus:reverse-prd` (whole-project) and confirm the v0.7.2 overwrite prompt. Loses all human edits across the entire PRD bundle — only worth it for projects with extensive code changes since the last reverse-prd.

Plugin manifest bumped to **0.7.1**. Pure additive vs v0.7.0 (no path migration, no orchestrator change, no test-fixture format change beyond the new keyword assertions).

## 12. v0.7.2 addendum — `/super-manus:reverse-prd` ergonomics

Two related improvements to `/super-manus:reverse-prd`, both surfaced by the v0.7.1 migration question (*"how do I get the new Exposes/Consumes fields into already-audited PRDs?"*).

### What changed

1. **Per-module mode** — `/super-manus:reverse-prd <module>` (with module-name argument) refreshes just `prd/<module>.md`. Skips Stage 1 module discovery, does not write `_index.md`, does not modify `roadmap.md`, does not touch other modules' files. After the refresh, the orchestrator runs a **cascade scan**: greps every other `prd/*.md` for case-sensitive mentions of the target module inside their `## How it connects` block, and checks `prd/_index.md ## Data flow overview` for edges involving the target. Surfaces the cascade as a follow-up list — does **not** silently regenerate.

2. **Soft-abort confirmation** — replaces the v0.7.0 hard-abort. The classification logic (uncommitted = empty / placeholder / `(audit ...)`; committed = real content) is unchanged; what changed is the action on `committed`:
   - **v0.7.0 / v0.7.1**: emit a refusal message, instruct the user to manually back up and clear the file. Hard stop.
   - **v0.7.2**: prompt via `AskUserQuestion`, listing exactly which file(s) will be overwritten. On user confirmation: proceed. On rejection: emit "Stopped — existing PRD preserved." and stop.

   Whole-project mode inspects `_index.md ## Problem`. Per-module mode inspects `prd/<module>.md ## Why this exists` (the analogous "this PRD has been authored" indicator at the per-module level).

### Why per-module mode

Three distinct use cases drove this:

- **Single-module code change** — "I refactored `parent-api` and want to refresh just that one module's PRD without re-running the whole project (and risking other modules' edits)."
- **Adopting v0.7.1 fields** — "Most of my PRD is audited and stable; I only want to fill `Exposes` / `Consumes` in one module without re-running everything." The per-module mode + soft-abort confirmation together turn this into a 1-command operation: `/super-manus:reverse-prd parent-api`, confirm, done.
- **Iterative architecture exploration** — "I'm experimenting with module boundaries. I want to refresh `module-A` after moving code in/out, without affecting how the rest of the PRD describes adjacent modules."

### Why cascade-scan reports rather than auto-regenerate

Auto-regeneration of dependent modules was rejected. Reasons:

- Violates per-module mode's contract ("one file in, one file out"). Users invoke per-module specifically to limit blast radius; expanding it would defeat the purpose.
- Conflicts with super-manus's **drift-aware** philosophy: PRD↔code drift is always surfaced and decided by the human, never silently fixed. The cascade scan extends the same principle to PRD↔PRD drift across modules.
- Implementation complexity: reliable dependency-graph derivation requires LSP `find-references` across module exports, which has cost; cheap grep-based reporting catches 90% of cases at near-zero cost.

`prd/_index.md ## Data flow overview` updates fall in the same bucket: the diagram is a global view, partial updates create internal inconsistencies. Cascade scan flags it; user decides whether a whole-project rerun is warranted.

### Why soft-abort confirmation rather than `--force` flag

Considered: `/super-manus:reverse-prd --force` to overwrite without prompting. Rejected because:

- Slash command argument-parsing is single-positional in Claude Code; `--force` would conflict with `<module>` (whole-project + force vs per-module).
- A flag is a footgun — easy to type once and bypass safety.
- Interactive confirmation already produces the right cost-benefit: the user sees exactly what's about to be lost, and can abort if they didn't realize. The friction is minimal (one click) but unskippable.

### Cascade implemented

- `commands/reverse-prd.md` — restructured with `## Mode resolution`, `## Confirmation gates`, mode-conditional discovery / spawning / post-conditions / user-facing messages. The `## Discover modules — runtime-first` section now explicitly opens with "whole-project mode only".
- `agents/reverse-prd-architect.md` — `## Inputs` gains `scope` + `target_module`; `## Deliverables` splits into `whole-project` and `single-module` contracts. Per-module deliverables forbid writing `_index.md` or any other `prd/<other>.md` even on discovered cascade.
- `tests/test_command_reverse_prd_logic.sh` — replaces `hard-abort` assertion with confirmation-gate assertions; adds per-module mode assertions (mode resolution, scope/target_module passing, cascade-scan requirement, "do NOT touch _index.md / roadmap.md").
- `tests/test_agent_reverse_prd_architect.sh` — asserts `scope` + `target_module` in inputs; asserts `single-module` deliverable contract (no `_index.md`, no other module files).

### Migration

Same backward-compatibility story as v0.7.1: pure additive. Existing whole-project invocations (no argument) continue to work unchanged; the only behavioral change is the hard-abort → confirmation switch on committed PRDs, which is strictly less restrictive.

Plugin manifest bumped to **0.7.2**. Pure additive vs v0.7.1.

## 13. v0.7.4 addendum — Reflexion-style cross-phase memory

Adds a fifth section `## Reflections` to `findings.md` plus two small orchestrator hooks. Closes a real gap surfaced during a v0.7.3 design review: the v0.7 reviewer↔writer feedback loop is **plain Reflection** (within-trial verdict echo), not **Reflexion** (cross-trial durable lesson). Plain Reflection patches the immediate bug; Reflexion turns repeated bugs into rules the next architect avoids by default.

### Structural mapping (Reflexion paper → super-manus)

| Reflexion component | super-manus realization |
| --- | --- |
| Actor | impl-architect / impl-test-writer / impl-code-writer |
| Evaluator | impl-reviewer at 3 checkpoints |
| Critic → Actor feedback (within-trial) | `previous_attempt_feedback` block on re-spawn (v0.7.0, already shipped) |
| **Self-reflection (root cause + heuristic)** | **NEW — orchestrator synthesizes at phase close** |
| **Episodic memory** | **NEW — `findings.md ## Reflections` (update-scoped, H3-keyed by phase)** |
| **Cross-trial context injection** | **NEW — next phase's architect spawning prompt includes prior `## Reflections`** |

The within-trial loop (already in v0.7.0) handles "this attempt was wrong, here's how the writer fixes it on retry". The new layer handles "the writer kept making mistake X within this update — phase N+1's architect should default to avoiding it". Two layers stacked; they don't compete.

### What changed

1. **`templates/findings.md`** gains a fourth H2: `## Reflections`. Append-only, H3-keyed by phase. Format per entry:

   ```markdown
   ### Phase <n>: <name>
   - Misstep: <one sentence — what attempt 1 got wrong; the surface event>
   - Root cause: <one sentence — why the writer made that choice>
   - Heuristic: <one sentence — rule for next phase to avoid this>
   ```

   Three bullets, fixed shape. The **Heuristic** line is the load-bearing one — it's what differentiates Reflections from `## Errors` (event log) and `## Session log` (chronological recap). If a phase closes with zero RETURN events, **no entry is written** — clean phases produce no reflection.

2. **`commands/impl.md` Step 9 (Phase close)** gains a **new first step** before flipping Status:
   - Read `$UPDATE_DIR/findings.md ## Errors` for rows tagged `phase p<n>` (review #1 / #2 / #3 RETURN events from THIS phase).
   - If ≥1 row exists, synthesize a `### Phase <n>: <name>` entry per the template above — orchestrator main thread does this inline, no new agent spawn.
   - Append (not prepend) to `findings.md ## Reflections`.
   - If 0 rows exist, skip — phase was clean on first try.
   - Then flip Status, run `refresh-outstanding.sh`, delete hash file (existing Step 9 actions).

3. **`commands/impl.md` Step 1 (Spawn impl-architect)** spawning prompt skeleton gets one new optional input:
   - `prior_reflections` — verbatim contents of `findings.md ## Reflections` if non-empty; absent if empty.
   - The orchestrator reads the section once before spawning; on subsequent re-spawns within the same phase (per existing v0.7.0 retry budget), the same value is reused.

4. **`agents/impl-architect.md` procedure** gains a new step 1.5 (between idempotency check and template seed):
   - "If your spawning prompt includes a `prior_reflections` block, read it before drafting. Each entry is `### Phase <m>: <name>` with Misstep / Root cause / **Heuristic** bullets — treat the Heuristic line as a checklist item to honor in this phase's `## Approach` and `## Files touched`. If a Heuristic genuinely doesn't apply to this phase (different module surface, different capability), say so in your summary line — don't silently ignore."

5. **`commands/impl-all.md` loop** mirrors impl.md: synthesis runs at each phase close inside the loop; the next phase's architect spawn includes the now-updated `prior_reflections`. Reflections accumulate across phases within a single `/super-manus:impl-all` run.

### Voice boundaries (load-bearing)

The three log layers in this update folder share a source-event ("phase 2 attempt 1 RETURN_TO_TEST_WRITER for inline-dict fixture") but record at different abstraction levels. Confusing them collapses Reflections back to a duplicate of `## Errors`:

| Layer | Voice | Audience | Example for the same source event |
| --- | --- | --- | --- |
| `findings.md ## Errors` | Atomic, structured, third-person | Orchestrator / reviewer audit trail | `\| 2026-05-08 \| review #2 attempt 1 RETURN_TO_TEST_WRITER \| inline dict fixture disagrees with head -1; suggested: re-fixture from real data \|` |
| `progress.md ## Session log` | Narrative, chronological | Human catching up on "what happened this week" | `- Closed phase 2 after re-fixturing tests on real data.` |
| `findings.md ## Reflections` | Heuristic, atemporal, prescriptive | Next phase's impl-architect (via spawning prompt) | `Heuristic: Run head -1 on every declared input source before drafting ## Approach; do not infer schema from PRD prose.` |

The Heuristic line is the test: if it reads as a rule a future architect could literally honor as a checklist item, it's a Reflection. If it reads as a recap of what occurred, it has drifted into Session log territory.

### Why orchestrator-as-synthesizer (not a new agent)

This was the design decision with the most candidates. Considered and rejected:

- **impl-reviewer writes Reflections** — reviewer has the cleanest root-cause analysis (it produced the verdict text). Rejected: reviewer's `tools: Read, Glob, Grep, Bash` — no `Write` / `Edit` — is a v0.7.0 load-bearing invariant. Reviewer being read-only by tool surface is what makes its audits trustworthy. Granting it Write to one file punctures that.
- **impl-architect writes Reflections** — architect has PM-voice synthesis chops. Rejected: architect's write surface is `tasks/p<n>_impl.md`. Phase-close is post-architect; re-waking it for a different file scope is a phase-end coda that doesn't fit its persona.
- **impl-test-writer / impl-code-writer write Reflections** — first-person voice fits Reflexion best. Rejected: writers are stateless single-spawn agents; adding a dedicated reflection turn means a 5th spawn per phase (~+15-25% cost).
- **New `impl-reflector` subagent** — clean separation. Rejected: agent sprawl for a low-frequency synthesis task. If quality of orchestrator-synthesized entries proves poor in practice, the upgrade path is to extract this step into `impl-reflector` later — zero migration cost.
- **Orchestrator main thread synthesizes** — chosen. The data is already in `findings.md ## Errors` (orchestrator wrote those rows itself on every RETURN). Phase close is already orchestrator-owned (Status flip, hash cleanup, refresh-outstanding). Adding "synthesize 3-bullet entry from this-phase ## Errors rows" is the same flavor of work.

This mirrors the existing **session log pattern**: hooks fire a checkpoint, the main agent judges + synthesizes + writes. v0.7.4 reuses the pattern at a different lifecycle point (phase close instead of every-N-turns / commit).

### Why update-scoped (not project-global)

Cross-update Reflections (project-global `docs/super-manus/reflections/<module>.md` accumulating heuristics across milestones) was considered. Rejected for v0.7.4:

- **Conflicts with the "PRD is target spec, no other source of truth" invariant.** A persistent reflections store would be a second long-lived doctrine file alongside PRD. If PRD and reflections diverge over months, which wins? Adding that adjudication channel needs its own design pass.
- **No retrieval matching.** Cross-update would want similarity matching (only feed reflections relevant to the current module's capabilities). Update-scoped sidesteps this — within one milestone (3-6 phases on one module), full-pool injection is fine signal/noise.
- **Reflexion paper does cross-trial-on-same-task.** Within one update, phases ARE near-similar tasks on the same module. Across updates, phases are different tasks. Update scope honors the paper's "similar task" precondition without retrieval logic.

If the update-scoped layer proves valuable in practice, cross-update is a separate v0.8 design discussion — at that point the questions become "where does it live", "how does it stay in sync with PRD evolution", "how is similarity defined", and those are too many decisions to bundle into v0.7.4.

### Cheat-prevention preservation

Same posture as v0.7.0:

- Reviewer is still read-only by tool surface — Reflections are written by the orchestrator main thread, not by the reviewer.
- The synthesis step runs **after** review #3 APPROVE — i.e., AFTER the cheat-prevention hash check has either passed or aborted the phase. A phase that aborts at the hash check writes no Reflection (the phase didn't close).
- Reflections cannot influence the within-phase test/code review chain — they're only consumed at the next phase's architect spawn, downstream of all current-phase reviews.

### Cascade implemented

- `templates/findings.md` — adds `## Reflections` H2 + embedded H3 template comment.
- `commands/impl.md` — Step 9 gains the synthesis sub-step; Step 1 spawning prompt gains `prior_reflections` input.
- `commands/impl-all.md` — loop pseudocode mentions reflection synthesis at each phase close.
- `agents/impl-architect.md` — `## Inputs` adds `prior_reflections`; procedure gains step 1.5 (read prior reflections, treat Heuristic lines as checklist).
- `skills/using-sm/SKILL.md` — `findings.md` description gains the `## Reflections` bullet.
- `CLAUDE.md` — schema list gains `## Reflections` for findings.md; "Where to look" gains v0.7.4 mention.
- `tests/test_template_findings.sh` — asserts `## Reflections` heading present.
- `tests/test_command_impl_logic.sh` / `tests/test_command_impl_all_logic.sh` — assert phase-close synthesis step + `prior_reflections` input.
- `tests/test_agent_impl_architect.sh` — asserts `prior_reflections` input documented.

### Migration

Pure additive. Existing `findings.md` files (no `## Reflections` section) work fine — the orchestrator's synthesis step is a no-op until it runs the first phase under v0.7.4 against an existing update folder, at which point it appends the new H2 (the heading-presence test on the template only checks templates, not active update files). No PRD schema change. No path migration. No phase-test format change. No hash baseline change.

Plugin manifest bumped to **0.7.4**. Pure additive vs v0.7.3.

### Out of scope (v0.7.4)

- **Cross-update reflections** (Option C in design discussion). Deferred — see "Why update-scoped" above.
- **Reflection retrieval / similarity matching.** Deferred with cross-update; not needed at update scope.
- **Reflection ESCALATION on persistent rule violation** (e.g., "architect violated Heuristic from Phase 1 in Phase 3 — escalate to user"). Considered overkill; the reviewer's existing checks catch the symptom even if the architect ignores the heuristic.
- **First-person voice enforcement** (writers produce reflections in their own voice rather than orchestrator synthesizing). Not worth the per-phase extra spawn at this point. If orchestrator-synthesized Heuristics prove generic / unhelpful, revisit.
- **Reflection visibility to reviewer.** Reflections are an architect-side input only. Reviewer continues to evaluate against PRD + plan + tests + code — adding "did architect honor Heuristic K?" to reviewer's checklist would re-couple the two layers we just separated.

## 14. v0.7.5 addendum — `ESCALATE_TO_USER` dual-layer voice

A real dogfood escalation (P4 picker latency, May 2026) surfaced a UX bug in the v0.7.0 reviewer: when a phase escalates to the user, the verdict block was structured for **engineer-to-engineer** consumption — heavy on jargon ("real-link bench RED", "plan §5 假设", commit hashes inline, no plain-language summary), with the result that the user reading it had to **re-derive** what was actually stuck before they could pick an option. The diagnostic facts were precise but front-loaded with terminology the user had to translate. The right voice fix is not "drop the facts" (those are load-bearing — without "27x slower than expected" the user cannot tell software-config from hardware-fundamental) but **layer two voices**: plain-language opener for "what happened?" + precise facts kept directly below for "what specifically?".

### What changed

`agents/impl-reviewer.md ## ESCALATE_TO_USER` template gains a four-section dual-layer body. The machine-parseable header (VERDICT / mode / phase / attempt) and the trailing `history:` block are unchanged — only the body between them is restructured:

```
VERDICT: ESCALATE_TO_USER
mode: <pre-test | pre-code | pre-close>
phase: p<n>
attempt: <attempt_number>

【发生了什么 / What happened】
<plain-language opener — 1–2 sentences, no jargon, no commit hashes>

【为什么不能自己解决 / Why the loop cannot converge】
<plain-language category — hardware physical limit / contradictory PRD / scope ambiguity / budget exhausted>

【关键事实 / Key facts】
- <numbers WITH comparison: "5.3s / 30 docs (plan §5 假设 <200ms — 27 倍慢)">
- <code state: commit hash, file, line>
- <PRD anchor: which `## section`, exact bullet text>
- <test/regression status>
- <suspicions / next-action diagnostic>

【你可以选 / Options】
[Recommended] (a) <plain-language + cost + outcome>
              (b) <option>
              (c) <option>
              (d) <option>

history:
  - attempt 1: <prior reviewer feedback if attempt > 1>
  - attempt 2: <prior reviewer feedback if attempt > 2>
```

### Voice rules (load-bearing)

Style rules baked into the template — agents/impl-reviewer.md spells these out so the reviewer doesn't drift back to single-voice output:

- **Plain-language voice in the top three labeled sections.** Pretend the reader is a smart PM who knows the project but does not know engineering jargon. "比目标还慢" beats "exceeds the SLO ceiling"; "改 1 行强制走 GPU" beats "explicit device='mps' in CrossEncoder init".
- **Numbers in `关键事实` carry units AND comparison.** Bare values are not actionable — `5.3s rerank latency` tells the user nothing without `(plan §5 假设 <200ms — 27 倍慢)`. The comparison is what makes the option chooser navigable.
- **`[Recommended]` marks exactly one option** when one path is clearly cheapest-to-test or highest-ROI. Mark none if there is no clear preference. **Never two.** False confidence misleads the user into a worse decision than leaving them to pick.
- **One line per option** — name + cost + outcome. The diagnostic facts above already supply context; do not write paragraphs in the chooser.
- **No commit hashes, file paths, function names in the top three sections.** Those go in `关键事实`. Top sections must read on a phone.
- **User's working language for headings.** Chinese projects → Chinese-led labels. The bilingual `【中 / EN】` form is the canonical fallback when language is unclear.

### Why dual-layer (not just plain-language)

Considered and rejected: drop the precise diagnostic block and write only plain-language. Why rejected:

- The user's option choice depends on the diagnostic numbers. Without "27x slower than expected", option (b) "MPS troubleshoot" is not obviously correct — the user could mistake it for fundamental hardware limit and pick (d) "accept SLO drift" instead. The numbers convert the diagnostic from opinion to evidence.
- Audit trail: weeks later when re-reading findings.md, "P4 escalated due to picker slow" is not enough — `commit 772c9e4 / 5.3s actual / 200ms planned` is the trace future-you needs.
- Cross-handoff: if the user accepts (d) "PRD edit", the next agent (`/super-manus:prd-update`) needs the exact PRD bullet text + plan section refs. Plain-language alone loses these handles.

Equally considered and rejected: keep engineer voice and let users translate. Why rejected:

- The dogfood case (`P4 review #3 ESCALATE_TO_USER ...`) showed the user explicitly asking for re-explanation in plain language before they could decide. That round-trip is preventable.
- super-manus's audience includes both technical leads and PMs — the latter cannot fluently parse "plan §5 §Approach §2/§3 commit 772c9e4". Output should be readable to both without translation.

### Cost impact

Negligible. The dual-layer template adds ~200 tokens to the agent's system prompt (loaded once per spawn, cache-hit after first within 5-min window) and ~200 tokens to the ESCALATE output (only when escalation actually triggers, which is rare — most phases never escalate). Per-phase amortized cost increase: <0.2%, fully dwarfed by writer model selection (frontmatter `model: sonnet` saves 60-70% — the dominant cost lever).

### Migration

Pure additive. v0.7.4 ESCALATE outputs continue to parse (header + history blocks unchanged). New format is opt-in by virtue of the agent's system prompt — every new reviewer spawn from v0.7.5 onward emits the new format; in-flight v0.7.4 spawns finish in old format. No findings.md / progress.md / PRD migration needed. No test fixture format change beyond the new keyword assertions.

### Cascade implemented

- `agents/impl-reviewer.md` — `## Verdict format ## ESCALATE_TO_USER` section: replaced single-block template with dual-layer template + style rules.
- `tests/test_agent_impl_reviewer.sh` — asserts presence of the four labeled sections, the `[Recommended]` marker rule, "no commit hashes in top sections" guidance, and the "both layers are load-bearing" non-collapse rule.
- `docs/design-v0.7.md` — this addendum.
- `.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` — version bumped to 0.7.5.

`commands/impl.md` and `commands/impl-all.md` are NOT modified — verdict consumption (parsing the `VERDICT: ESCALATE_TO_USER` line, surfacing user_options) is structurally unchanged. The orchestrator forwards the verbatim verdict body to the user via the existing `Surface to user verbatim` step.

### Out of scope (v0.7.5)

- **Reformatting RETURN_TO_<writer> verdicts.** Those go to a writer agent, not the user — engineer voice is correct there. The dual-layer is specifically for user-facing output.
- **Reformatting APPROVE notes.** APPROVE is informational and rarely consequential; engineer voice is fine.
- **Translating existing v0.7.4 ESCALATE outputs.** History stays history; new format applies forward only.
- **Auto-rendering as a UI chooser.** That is a Claude Code SDK / harness concern, not super-manus's. The agent still emits text; whoever renders it can apply UI affordances.
- **Per-project voice tuning** (e.g., let teams add `## Reviewer voice override` to PRD). YAGNI — bilingual fallback covers the realistic spread.

Plugin manifest bumped to **0.7.5**. Pure additive vs v0.7.4.
