# super-manus — Design Doc (v0.5)

> **SUPERSEDED by [docs/design-v0.6.md](design-v0.6.md).** v0.5's 3-agent impl pipeline, e2e regression suite, three execution skills, and `/super-manus:impl-all` are all preserved in v0.6. The only delta in v0.6 is repositioning `/super-manus:prd-update` from drift-absorption-only to forward-iteration + drift-absorption (mode auto-detected from `prd_drift.md`). Layout, agents, hooks, and the end-of-update drift gate are unchanged. Kept for historical reference of the v0.5 design rationale.
>
> Supersedes [docs/design-v0.4.md](design-v0.4.md) (v0.4 — project-global PRD layout, single impl-architect agent), [docs/design-v0.2.md](design-v0.2.md) (v0.2/v0.3 — per-feature wrapper folder layout), and [docs/design-v0.1.md](design-v0.1.md) (v0.1 — flat single-PRD layout).

## 1. What changed from v0.4

v0.4 nailed the project-global PRD layout but left three gaps:

1. **Execution discipline was outsourced.** v0.4 was meant to coexist with [obra/superpowers](https://github.com/obra/superpowers) for TDD / verification / debugging. In practice many of superpowers' skills (brainstorming, plan writing, plan execution, subagent dispatch) overlap with super-manus's own commands; only TDD / verify-before-completion / systematic-debugging actually fit. Coexistence created a dual-mental-model burden for users.
2. **Single impl-executor would let one agent both write tests and write code**, opening the obvious cheating modes: weak tests, post-hoc test adjustment, tautological test↔impl mirroring.
3. **No permanent regression suite tied to PRD.** v0.4 had no concept of "tests that prove a `## What users get` capability still works after future milestones". Each update's tests came and went with the milestone; system-level e2e coverage was implicitly the user's responsibility.

v0.5 closes all three gaps:

- **super-manus is self-sufficient.** Three skills absorbed from superpowers (TDD discipline scoped to phases, verification before phase-close, systematic debugging in a phase). No more "install superpowers alongside" — super-manus ships its own thin execution layer.
- **`/super-manus:impl` runs three agents in series with a write-permission trust boundary**: planner → test-writer → code-writer. All three agents READ everything (PRD, plan, source code, prior tests). The boundaries are temporal (test-writer commits red tests BEFORE code-writer runs) and write-permission (code-writer cannot modify test files). Orchestrator hashes the tests after test-writer commits and re-checks after code-writer commits — any tamper aborts the phase with a warning. Cheat-prevention is enforced via persona discipline ("write tests from PRD spec, NOT from impl plan"), not by hiding files from the test-writer.
- **Two-tier test maintenance.** test-writer maintains both (1) **phase tests** scoped to one update at `docs/super-manus/impl/<m>/<u>/tests/phase_p<n>_*.{ext}` (milestone proof, NOT auto-discovered by CI), and (2) **e2e tests** at `docs/super-manus/e2e/<module>/test_<capability>.{ext}` and `docs/super-manus/e2e/_system/test_<scenario>.{ext}` — permanent regression suite mirroring PRD's module/_index structure. e2e tests are auto-discovered by pytest/jest; CI runs them on every commit.
- **End-of-update drift gate gains Pass 3 — e2e coverage check.** For every `## What users get` capability the update touches, there must be a corresponding `e2e/<module>/test_<capability>.{ext}` that exists AND passes. Missing e2e → drift row, BLOCKS roadmap stable.
- **Karpathy guidelines** ([andrej-karpathy-skills:karpathy-guidelines](https://github.com/andrejs-skills)) referenced from both impl-test-writer and impl-code-writer personas — surgical changes, surface assumptions, define verifiable success criteria, avoid overcomplication.

## 2. Layout

```
docs/super-manus/
├── prd/                                     ← project-global, ONE source of truth
│   ├── _index.md                            ← 8 PM-flavored H2 sections
│   └── <module>.md                          ← 9 PM-flavored H2 sections
├── e2e/                                     ← NEW in v0.5: permanent regression, mirrors prd/
│   ├── _system/                             ← cross-module scenarios from prd/_index.md ## Demo
│   │   └── test_<scenario>.py               ← test_*.py is auto-discovered by pytest; runs in CI
│   └── <module>/                            ← per-module capability tests from prd/<module>.md ## What users get
│       └── test_<capability>.py             ← ditto, auto-discovered, runs in CI
├── roadmap.md                               ← project-global
├── prd_drift.md                             ← project-global, append-only
└── impl/                                    ← time series of milestones, per module
    └── <module>/
        └── <YYYY-MM-DD>-<update-name>/
            ├── task_plan.md
            ├── findings.md
            ├── progress.md
            ├── tasks/
            │   └── p<n>_impl.md
            └── tests/                       ← NEW in v0.5: phase tests, milestone-scoped
                ├── phase_p1_<verb>_<noun>.py    (Python; pytest skips `phase_*` by default)
                ├── phase_p2_<verb>_<noun>.phase.ts (Node/TS; jest skips `*.phase.ts` by default)
                └── ...
```

**Two visible v0.5 layout additions: `e2e/` (permanent) and `impl/<m>/<u>/tests/` (milestone-scoped).** They're not interchangeable — see §6 for the decision rules and naming-convention rationale.

## 3. The 3-agent /super-manus:impl orchestration

```
/super-manus:impl
  │
  ▼
orchestrator: resolve target → pick next pending phase → drift check
  │
  │ no drift, drift gate clear
  ▼
[1] spawn impl-architect
       (existing agent from v0.4)
       writes: tasks/p<n>_impl.md (Objective / Approach / Files touched / Verification)
       does NOT write code or tests
  │
  ▼
[2] spawn impl-test-writer  (NEW in v0.5)
       reads (priority order):
         [primary]   prd/<module>.md (full 9 sections)              ← spec, mandatory
         [primary]   prd/_index.md (## Demo, ## Audience,
                       ## Success metrics, full sections)           ← scenario, mandatory
         [secondary] tasks/p<n>_impl.md ## Objective                ← phase scope
         [secondary] tasks/p<n>_impl.md ## Verification             ← avoid duplicate coverage
         [secondary] prior phase tests + e2e/<module>/test_*.{ext}  ← prior coverage
         [context]   tasks/p<n>_impl.md ## Approach + Files touched ← context only, do NOT mirror
         [context]   source code + LSP                              ← API surface (class/fn names)
       persona discipline: "tests validate PRD spec, NOT mirror impl plan"
       writes:
         (a) tests/phase_p<n>_*.{ext}                       ← always, milestone-scoped
         (b) e2e/<module>/test_<capability>.{ext}           ← when this phase
                                                              completes a ## What users get
                                                              capability (new or extended)
         (c) e2e/_system/test_<scenario>.{ext}              ← when this phase completes
                                                              a cross-module ## Demo scenario
       runs:   all newly-written/extended tests, expects ALL FAIL (red) for new, prior e2e
                                                              should still pass for old caps
       commits: only test files (phase + e2e)
       returns: "wrote N phase tests + M e2e tests, all currently red as expected"
  │
  ▼
orchestrator: snapshot SHA-256 of every tests/phase_p<n>_*.{ext} AND every
              e2e/<module>/test_*.{ext} touched
  │
  ▼
[3] spawn impl-code-writer  (NEW in v0.5)
       reads: full PRD, tasks/p<n>_impl.md (all 4 sections),
              tests/phase_p<n>_*.{ext} (READ-ONLY),
              e2e/<module>/test_*.{ext} (READ-ONLY)
       writes: source code per ## Approach + ## Files touched
       runs:   phase tests + touched e2e tests, iterates until ALL pass (green)
       commits: source files only
       returns: "all N phase tests + M e2e tests pass"
       MUST NOT: edit any test file under tests/ or e2e/
  │
  ▼
orchestrator: re-hash all test files snapshotted in step 2, compare
  │  if mismatch → ABORT phase, append drift row "code-writer modified tests",
  │             surface to user, do NOT flip phase status
  ▼
orchestrator: run every command in tasks/p<n>_impl.md ## Verification
  │  if any fail → invoke systematic-debugging-in-phase skill, do NOT flip phase
  ▼
flip phase Status to closed in task_plan.md
  │
  ▼
[command-dependent terminal behaviour]
  /super-manus:impl       (one-phase mode):
    if more pending phases → STOP. Tell user the phase shipped + which is next.
                             User re-invokes /super-manus:impl to continue.
    if no more pending     → fall through to end-of-update drift gate (§8, 3-pass).
  /super-manus:impl-all   (loop mode):
    if more pending phases → restart from drift check at top, no pause.
    if no more pending     → fall through to end-of-update drift gate.
```

The split between `/super-manus:impl` and `/super-manus:impl-all` is purely a control-flow choice at the loop boundary. The 3-agent pipeline inside one phase is identical for both commands.

The architect / test-writer / code-writer split exists for one reason: **prevent the implementing agent from gaming its own tests.** A single agent that writes both tests and impl has obvious motives to write weak tests, adjust expectations after seeing the impl, or produce tautological mirror-tests. v0.5 closes these via three independent mechanisms:

1. **Time barrier** — test-writer commits red tests BEFORE code-writer runs. By the time code-writer is spawned, tests are in git; there is no "future impl" for tests to mirror.
2. **Write barrier** — code-writer's persona forbids editing any file under `tests/` or `e2e/`; orchestrator hashes test files before/after code-writer and aborts on mismatch.
3. **Persona discipline** — test-writer's persona explicitly anchors tests in PRD spec (`## What users get`, `## Quality bar`, `## Risks`, `## Demo`), treating `## Approach` as one-of-many valid implementations and refusing to mirror it.

Read access is OPEN — test-writer reads everything (PRD, full impl plan, source code, prior tests). The cheat-prevention boundaries are temporal + write-permission + persona, not read-permission. This matches normal TDD: a human developer writing both test and impl knows the impl plan, but discipline (and skin-in-the-game) keeps tests anchored in spec. We replace skin-in-the-game with explicit persona instructions + the time/write barriers above.

The split does NOT close the "minimum impl that passes" cheat — that's intrinsic to TDD. The end-of-update drift gate (Pass 1 reconciles commits vs PRD `## What users get`; Pass 3 enforces e2e coverage) is the backstop.

## 4. Agent architecture (5 named agents in v0.5)

| Agent | Spawned by | Role | Tools |
| --- | --- | --- | --- |
| `reverse-prd-architect` | `/super-manus:reverse-prd` | one-shot full PRD bundle generator from existing source | Read, Write, Edit, Glob, Grep, Bash |
| `sync-planner` | `/super-manus:sync` | PRD-diff → 3–6 candidate Phases | Read, Grep, Glob, Bash |
| `impl-architect` | `/super-manus:impl` step 1 | drafts `tasks/p<n>_impl.md` for one phase | Read, Write, Edit, Glob, Grep, Bash |
| **`impl-test-writer`** | `/super-manus:impl` step 2 | writes phase tests (red); read-only on source | **Read, Write, Glob, Grep, Bash** (no Edit) |
| **`impl-code-writer`** | `/super-manus:impl` step 3 | writes implementation; read-only on tests | **Read, Write, Edit, Glob, Grep, Bash** (Edit forbidden on tests/ via prompt) |

Each agent has a matching `tests/test_agent_<name>.sh` per the CLAUDE.md repo invariant.

The two new agents (`impl-test-writer`, `impl-code-writer`) both reference `andrej-karpathy-skills:karpathy-guidelines` in their persona — keep changes surgical, surface assumptions, define verifiable success criteria, avoid overcomplication. The skill stays externally maintained (we don't fork it).

## 5. Three new skills (v0.5)

Lives under `skills/<name>/SKILL.md` alongside the existing `skills/using-sm/`.

### `tdd-in-phases`

When `/super-manus:impl` enters a phase, the test-writer is spawned BEFORE the code-writer. This is non-negotiable. The skill enforces:

- Test files MUST be written at `docs/super-manus/impl/<m>/<u>/tests/phase_p<n>_<verb>_<noun>.<ext>`.
- Tests SHOULD be derived from `prd/<module>.md ## What users get` capabilities + `prd/_index.md ## Demo` scenarios. Unit-level + scenario-level both allowed; e2e where the capability is end-user-facing.
- Test-writer commits the tests with all of them currently failing (red bar).
- Code-writer does NOT skip tests, does NOT modify tests. If a test seems wrong, escalate to user.
- After the phase: code-writer's commits flip every test green. Orchestrator re-runs tests as part of phase-close verification.

### `verification-before-phase-close`

Phase Status flips to `closed` only after every command listed in `tasks/p<n>_impl.md ## Verification` exits green. The orchestrator (not the code-writer) runs them. Failed verify → systematic-debugging-in-phase skill kicks in; phase stays in_progress.

`## Verification` MUST include at minimum: (1) the path to phase tests for this phase (`pytest docs/super-manus/.../phase_p<n>_*.py` or equivalent), and (2) one user-visible smoke command (curl an endpoint, run a CLI, open a page) that confirms the capability actually works end-to-end, not just in unit tests.

### `systematic-debugging-in-phase`

When a verify command fails, do NOT randomly try fixes. Follow the checklist:

1. Re-read `tasks/p<n>_impl.md ## Approach` — was an assumption violated?
2. Re-read the failing phase test — what exactly does it expect that isn't delivered?
3. Binary-search: comment out half the changed lines, re-run; narrow the failure.
4. Write a regression test capturing this failure mode (in `tests/phase_p<n>_*.{ext}` if the orchestrator allows; else in `findings.md` reproduction notes).
5. Fix; re-run all phase tests; re-run all `## Verification` commands.

If the checklist completes without a clear cause, append a row to `findings.md ## Errors` describing the symptom + what was tried, and surface to the user. Do NOT keep iterating blindly.

## 6. Phase tests vs e2e tests

The two test tiers serve different purposes and have different lifecycles. test-writer maintains both.

### Tier comparison

| | **Phase tests** | **e2e tests** |
| --- | --- | --- |
| Scope | one phase of one update | a complete `## What users get` capability OR a `## Demo` scenario |
| Path | `docs/super-manus/impl/<m>/<u>/tests/phase_p<n>_*.{ext}` | `docs/super-manus/e2e/<module>/test_<capability>.{ext}` or `docs/super-manus/e2e/_system/test_<scenario>.{ext}` |
| Lifetime | committed with the milestone; archived after `roadmap.md` flips to `stable`; may be deleted with the update folder | permanent; lives as long as the capability lives in PRD |
| Auto-discovered by CI? | NO — `phase_*` prefix or `*.phase.ts` suffix is outside default test runner globs | YES — `test_*.py` / `*.test.ts` matches default patterns |
| When written | every phase | when this phase **completes** a `## What users get` capability (new or extended); or when scenario in `prd/_index.md ## Demo` becomes deliverable |
| Decision | mandatory per phase | conditional per phase — see decision rule below |

### When test-writer writes an e2e test

```
test-writer's decision per phase:

read prd/<module>.md ## What users get + tasks/p<n>_impl.md ## Objective
   ↓
this phase's objective intersects which capability bullets?
   ↓
for each intersected capability:
   ↓
is this capability *complete* after this phase?
   - YES (this is the last/only phase delivering this capability)
       → write e2e/<module>/test_<capability>.{ext} (new or extend)
   - NO (this capability spans multiple phases, this is intermediate)
       → skip e2e for this capability this phase
       → e2e gets written when the LAST phase completing it runs
   ↓
also: if this phase completes a cross-module ## Demo scenario from
prd/_index.md, write/extend e2e/_system/test_<scenario>.{ext}.
```

If unsure whether a capability is "complete" — check the `task_plan.md ## Phases` table for remaining phases that touch the same capability. If none remain, this phase is the last one; write e2e. If unsure, default to `(audit — capability completion uncertain; please confirm whether to write e2e)` rather than guessing.

### Naming conventions per language

| Project's runtime | Phase test naming | e2e test naming | Notes |
| --- | --- | --- | --- |
| Python (pytest) | `phase_p<n>_<verb>_<noun>.py` (NOT discovered) | `test_<capability>.py` (auto-discovered) | pytest picks up `test_*.py` recursively; `phase_*` skipped |
| Node (jest) | `phase_p<n>_<verb>_<noun>.phase.ts` (NOT discovered) | `<capability>.test.ts` (auto-discovered) | jest default: `*.test.ts`; `*.phase.ts` skipped |
| Vitest | `phase_p<n>_<verb>_<noun>.phase.ts` | `<capability>.test.ts` | same as jest |
| Go | NOT under super-manus; written alongside source as `<pkg>/<feature>_test.go` per Go convention | `<pkg>/<feature>_e2e_test.go` (or `tests/e2e/...`) | Go strictly requires co-location for unit tests; integration/e2e can live elsewhere |
| Rust | `tests/phase_p<n>_<verb>_<noun>.rs` (integration, in super-manus folder) | `docs/super-manus/e2e/<module>/<capability>.rs` (integration test) | Rust integration tests are flexible |
| Java/Maven | NOT under super-manus | `src/test/java/.../<Capability>E2eTest.java` | Maven enforces structure |

For Go / Java projects, impl-test-writer probes the project's language ecosystem (pyproject.toml / package.json / go.mod / pom.xml / Cargo.toml) and falls back to writing tests at the project's required location while preserving the naming distinction (`phase_*` vs `e2e_*` prefix/suffix to identify origin).

### CI implications

```yaml
# Recommended .github/workflows/ci.yml split:

- name: Project's pre-existing tests
  run: pytest tests/                       # untouched by super-manus

- name: super-manus e2e suite (permanent regression)
  run: pytest docs/super-manus/e2e/        # PRD-derived, runs every commit

# Phase tests are NOT in CI — they are run only by /super-manus:impl
# during phase execution. After milestone closes, phase tests stay as
# historical record but are not part of the regression set.
```

The split is intentional: phase tests are "milestone-proof" (they prove the phase shipped), e2e tests are "permanent contract" (they prove the capability still works). To promote a phase test to permanent regression, the user manually moves it from the update folder to `e2e/<module>/` and renames per the e2e convention.

## 7. Slash command surface (v0.5 splits `impl` into two; otherwise unchanged from v0.4)

| Command | Role |
| --- | --- |
| `/super-manus:start` | (no args) idempotent enable in current project |
| `/super-manus:brainstorm` | 6-question Q&A producing PRD content |
| `/super-manus:reverse-prd` | one-shot scan of existing project, generates PRD |
| `/super-manus:sync <module>` | reads PRD-diff, drafts Phases via `sync-planner`, scaffolds update folder |
| **`/super-manus:impl`** | **(NEW v0.5 semantic)** run ONE phase end-to-end (architect → test-writer → code-writer → verify → close), then stop. If that was the last pending phase, run end-of-update drift gate. Conservative default — one user invocation = one phase shipped. |
| **`/super-manus:impl-all`** | **(NEW in v0.5)** loop through ALL pending phases of the active update without pausing. Each phase still goes architect → test-writer → code-writer → verify → close. After last phase, run end-of-update drift gate. For when the plan is already audited and you want to ship the whole milestone in one go. Subject to all the same drift checks; just no pauses between phases. |
| `/super-manus:prd-update <module>` | surgical PRD edit |
| `/super-manus:drive` | global "what should I do next" decider |
| `/super-manus:catchup` | re-inject most-recent update + project-global PRD index |
| `/super-manus:log` | manual session log entry |

### When to use which

- **`/super-manus:impl`** — DOGFOOD default. Use when:
  - You don't fully trust impl-architect's plan yet (want to inspect each phase plan before tests/code are written)
  - Working on an unfamiliar module
  - Want a natural git history with one milestone phase per "session"
  - Need to context-switch between phases (e.g., wait for a teammate, get review)

- **`/super-manus:impl-all`** — POWER MODE. Use when:
  - You've already reviewed `task_plan.md ## Phases` and trust the breakdown
  - The module is well-understood and architectural surprises are unlikely
  - You want to "ship the milestone" and come back when it's done (or blocked)
  - CI / nightly automation context

Both go through identical agent spawns, drift checks, and end-of-update gate. The ONLY difference is whether the orchestrator pauses between phases. **An aborted `impl-all` (Ctrl-C, agent error, drift detected, tamper detected, gate failed) leaves work in the same on-disk state as if `impl` had run that many times** — so falling back from `impl-all` to `impl` mid-stream is safe.

## 8. Drift control

Three trigger points (unchanged from v0.4):

- `/super-manus:sync` — reads PRD diff. Drift impossible by construction (intent IS the PRD diff).
- `/super-manus:impl` step "drift check" — phase intent vs PRD `## What users get` / `## Quality bar` / `## Out of scope`. Runs BEFORE spawning agents.
- `/super-manus:drive` — global drift scan: recent commits ↔ PRD.

**v0.5 adds an implicit fourth check** during `/super-manus:impl`: between impl-test-writer and impl-code-writer, the orchestrator hashes test files; after code-writer claims done, the orchestrator re-hashes. Tamper → drift row "code-writer modified tests for phase p<n>", phase aborted, user must investigate. This is mechanical; no LSP needed.

### End-of-update drift gate (BLOCKING, now 3-pass in v0.5)

When all phases of an update are `closed`, orchestrator runs three passes in order. Update is NOT done until all three pass.

**Pass 1 — Refresh drift from this update's commits.** Read `prd/<module>.md` (`## What users get`, `## Quality bar`, `## Out of scope`) + this update's `progress.md ## Completed commits`. For each:
- Bullet in `## What users get` / `## Quality bar` not reflected by any commit → append `pending` row "declared but not in commits".
- Capability visible in commits but not declared in PRD → append `pending` row "shipped but not in prd/<module>.md".

**Pass 2 — e2e coverage check (NEW in v0.5).** For each `## What users get` capability touched by this update's commits:
- Verify `docs/super-manus/e2e/<module>/test_<capability>.{ext}` exists.
- Run it. Must pass.
- Missing or red → append `pending` row "missing e2e coverage for capability X" or "e2e for capability X is red".

For each cross-module `## Demo` scenario completed in this update:
- Verify `docs/super-manus/e2e/_system/test_<scenario>.{ext}` exists and passes.
- Same `pending` rules.

**Pass 3 — Block until pending = 0.** Read `docs/super-manus/prd_drift.md`. Count rows where `Module = $MODULE` AND `Resolution = pending`.
- `pending > 0` → BLOCKED. Print rows; suggest `/super-manus:prd-update` (for "shipped but not declared") or revert (for "declared but not built") or write missing e2e (for Pass 2 violations). STOP. Do NOT flip roadmap to stable.
- `pending == 0` → flip roadmap row from `iterating` to `stable`. Update done.

`/super-manus:prd-update` flips a row's Resolution from `pending` to `prd-update: <option-letter>`, which automatically unblocks on next `/super-manus:impl` invocation. For Pass 2 violations, the resolution path is to write the missing e2e (re-spawn impl-test-writer with `e2e_only=true` mode) and then re-run the gate.

## 9. Migration from v0.4

Pure additive — no path changes:

- v0.4 update folders gain a `tests/` subdirectory the next time `/super-manus:impl` runs in them (created on demand by impl-test-writer).
- v0.4 commands/impl.md is replaced; the new orchestrator spawns 3 agents instead of one. Old phase plans (already in `tasks/p<n>_impl.md`) are reused as-is by impl-architect's idempotent path (existing rule).
- v0.4 projects gain a `docs/super-manus/e2e/` directory the first time impl-test-writer needs to write an e2e test (created on demand). The first run on an existing v0.4 project produces e2e tests for whichever capabilities the running phase completes; older capabilities don't get e2e coverage retroactively unless the user manually adds them.
- v0.4 `roadmap.md` / `prd_drift.md` / `prd/` files are unchanged.
- Plugin manifest version bumps to 0.5.0.

If the user installed `obra/superpowers` alongside super-manus on v0.4, no action required: superpowers can stay installed, but v0.5 super-manus no longer needs it. Uninstall via `/plugin uninstall superpowers` if you don't use it for non-super-manus work.

## 10. Out of scope (v0.5)

- Strict no-read isolation between test-writer and code-writer (option 2a in the v0.5 brainstorm — code-writer flying blind would multiply iteration cost without proportional cheat-prevention; v0.5 takes the open-read + write-barrier + persona-discipline path; revisit in v0.6 if cheating data justifies tightening)
- Code review skill / agent (deferred — `## Verification` + 3-pass drift gate covers the load-bearing checks for now)
- Retroactive e2e-coverage backfill for v0.4 projects (manual — write e2e for old capabilities yourself, or wait until a future phase touches that capability and the test-writer adds e2e then)
- Auto-promote phase test to e2e suite (manual move + rename per §6 conventions)
- Multi-product monorepo support in a single super-manus folder (still: use multiple super-manus-enabled subdirectories)
- Auto-migration of phase tests when a `module` rename happens (manual until rename command exists)
- Code-writer execution timeouts / wall-clock budget enforcement (deferred — current `(audit)` rule is "if you're stuck, escalate")

## 11. Plugin version

v0.5.0 (additive vs v0.4: new skills, new agents, new orchestration; no path migration). Plugin manifest at `.claude-plugin/plugin.json` is the canonical version source.
