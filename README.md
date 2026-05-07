# super-manus

> 🌐 **Languages**: **English** · [简体中文](README.zh-CN.md)

A Claude Code plugin for **PRD-led, drift-aware development**. State lives on disk and survives `/clear` and `/compact`. Each milestone runs through a 4-agent TDD pipeline (architect → test-writer → code-writer, with a read-only reviewer at three checkpoints); the implementing agent has no permission to edit its own tests, and reviewer verdicts drive a re-spawn loop until the phase converges. A blocking drift gate refuses to mark work "done" while the per-module PRD and the actual code disagree.

Self-sufficient — ships with TDD / verification / debugging skills. No other workflow plugin required.

## Install

**Recommended — marketplace:**

```
/plugin marketplace add https://github.com/lianghaofeng/super-manus-skill
/plugin install super-manus@super-manus-skill
```

Future updates via `/plugin marketplace update super-manus-skill`.

**Local marketplace** (local development, or remote install fails):

```
/plugin marketplace add /path/to/super-manus
/plugin install super-manus@super-manus-skill
```

Restart Claude Code after first install so hooks and slash commands register.

## How to use it

The daily loop is small: write a PRD once, then iterate by editing PRD bullets and running phases. Everything is one slash command.

### Command reference

| Command | When to run | What it does |
|---|---|---|
| `/super-manus:start` | once per project | Seeds `docs/super-manus/prd/`, `impl/`, `roadmap.md`, `prd_drift.md` (`e2e/` is created lazily by `impl-test-writer` when the first capability ships). |
| `/super-manus:brainstorm` | new project | 6-question PM interview → writes `prd/_index.md` + per-module `prd/<module>.md` stubs. |
| `/super-manus:reverse-prd` | existing project, no PRD yet | Reads code (runtime-first module discovery), writes `prd/_index.md` (with ASCII arch diagram) + module stubs. |
| `/super-manus:prd-update <module>` | adding a capability OR resolving drift | Structured 5-option edit on one `prd/<module>.md`: **add / tighten / split / demote / exclude**. Mode (forward iteration vs drift absorption) is auto-detected. |
| `/super-manus:sync <module>` | after a PRD edit | Reads `git diff prd/<module>.md`, drafts 3-6 candidate phases, scaffolds the milestone folder. |
| `/super-manus:impl` | iterate one phase | Runs ONE phase end-to-end (architect → review → test-writer → review → code-writer → review → verify → close), then stops. Reviewer at 3 checkpoints (pre-test / pre-code / pre-close) drives a re-spawn loop with per-checkpoint retry budget. |
| `/super-manus:impl-all` | finish a milestone | Loops through ALL pending phases of the active update without pausing. Same 4-agent pipeline + 3 review checkpoints + drift checks per phase. |
| `/super-manus:drive` | "what next?" | Reads everything, picks one of the above, announces decision + reason, executes. |
| `/super-manus:catchup` | new session | Re-injects PRD overview + active update's task_plan into context. |
| `/super-manus:log` | manual checkpoint | Append a session log entry to the active update's `progress.md` now. |

### `/super-manus:prd-update` — the five edit options

PRD edits are structured, not freeform. One bullet at a time. The command's prompt presents these in a–e order:

| Letter | Option | Use when | Effect |
|---|---|---|---|
| **a** | Tighten | a claim is too vague | Rewrite a bullet with sharper user-visible language + technical evidence. |
| **b** | Split | one bullet covers two distinct capabilities | Replace one bullet with two, both individually auditable. |
| **c** | Demote | a bullet was overpromised | Move it to `## Open questions`. |
| **d** | Exclude | a bullet is no longer in scope | Move it to `## Out of scope`. |
| **e** | Add | a new capability | Append a bullet to `## What users get`. |

After any edit, run `/super-manus:sync <module>` to scaffold the next milestone.

### Example 1 — green-field project, end to end

```bash
# 1. Bootstrap
/super-manus:start
/super-manus:brainstorm
# 6 PM-style questions, last one is module split.
# Writes prd/_index.md + per-module stubs at not-started.

# 2. You audit prd/api.md and flesh out ## What users get with
# the actual capabilities. PM voice, ~2000 words max.

# 3. Cut the first milestone for the api module
/super-manus:sync api
# Reads `git diff prd/api.md`, sync-planner agent drafts 3-6 phases.
# Creates docs/super-manus/impl/api/2026-05-07-bootstrap/
# with task_plan.md (phases) + findings.md + progress.md.
# You review the phases, edit if needed.

# 4. Ship the milestone
/super-manus:impl-all
# For each pending phase:
#   - impl-architect drafts tasks/p<n>_impl.md
#   - impl-reviewer (pre-test)  → APPROVE / RETURN to architect
#   - impl-test-writer commits red phase + e2e tests
#   - impl-reviewer (pre-code)  → APPROVE / RETURN to test-writer or architect
#   - impl-code-writer writes src until tests green
#   - impl-reviewer (pre-close) → APPROVE / RETURN to any upstream writer
#   - orchestrator hash check + runs ## Verification commands
# Per-checkpoint retry budget: 2 RETURNs max; 3rd RETURN escalates to user.
# End-of-update: drift gate refuses to flip roadmap → stable
# unless e2e covers every touched ## What users get capability.
```

### Example 2 — adding a capability mid-stream

You realize the API needs rate limiting. Don't go write code — write the PRD first.

```bash
# 1. Surface the new capability through the PRD
/super-manus:prd-update api
# Pick "add" → answer 2-3 questions about the new bullet.
# Edits prd/api.md ## What users get directly.
# Forward-iteration mode auto-detected (no drift row exists).

# 2. Cut a milestone for the new capability
/super-manus:sync api
# Reads the prd/api.md diff, drafts phases for "rate limiting".
# Scaffolds docs/super-manus/impl/api/2026-05-07-rate-limiting/.

# 3. Ship it
/super-manus:impl-all
```

### Example 3 — code drifted from PRD

While implementing, you added a metrics endpoint that wasn't in PRD. The drift checker stops you and appends a `pending` row to `prd_drift.md`. Two paths:

```bash
# Path A — revert the code, stay aligned with PRD.
git revert <commit>

# Path B — let PRD catch up to the code (drift absorption).
/super-manus:prd-update api
# Drift mode auto-detected (pending row exists for api).
# Pick "add" to legitimize the metrics endpoint.
# Writes a paired Decision into the active findings.md;
# flips prd_drift.md row's Resolution from `pending`.
# End-of-update gate now unblocks.
```

### Example 4 — onboarding an existing project

```bash
# Project has code but no PRD.
/super-manus:start
/super-manus:reverse-prd
# orchestrator does runtime-first module discovery (compose /
# Makefile / apps / scripts), then spawns reverse-prd-architect
# (chief architect + senior PM persona) which writes
# prd/_index.md (with mandatory ASCII architecture diagram)
# + per-module stubs.

# 2. Audit (audit) markers — wherever the architect hedged, you
# fill in or correct. Then per module:
/super-manus:sync <module>
/super-manus:impl-all
```

### When in doubt

```bash
/super-manus:drive
# Reads PRD + roadmap + active update + drift log, picks one of
# brainstorm / sync / prd-update / impl, announces what it picked
# and why, then executes.
```

## Directory layout

The on-disk layout super-manus creates inside a project that uses it:

```
<project-root>/
└── docs/super-manus/
    ├── prd/                                    # project-global, ONE source of truth
    │   ├── _index.md                           # project overview + module manifest + data flow (≤700 words)
    │   └── <module>.md                         # per-module target state (≤2000 words)
    ├── e2e/                                    # permanent regression suite, mirrors prd/ (lazy — created by impl-test-writer on first capability)
    │   ├── _system/
    │   │   └── test_<scenario>.<ext>           # cross-module ## Demo scenarios; auto-discovered, runs in CI
    │   └── <module>/
    │       └── test_<capability>.<ext>         # per-module ## What users get capabilities; auto-discovered
    ├── roadmap.md                              # project-global, module status table (auto-managed)
    ├── prd_drift.md                            # project-global, PRD ↔ implementation drift log (append-only)
    └── impl/                                   # time series of milestones, per module
        └── <module>/
            └── <YYYY-MM-DD>-<update-name>/     # only place timestamps appear
                ├── task_plan.md                # phase index for this update (Goal + Phases table)
                ├── findings.md                 # decisions / errors / data points for this update
                ├── progress.md                 # commits + session log for this update (hook-managed)
                ├── tasks/
                │   └── p<n>_impl.md            # per-phase technical plan (lazy)
                └── tests/
                    └── phase_p<n>_<verb>_<noun>.<ext>  # phase tests, milestone-scoped, NOT auto-discovered
```

**Two axes** (no overlap):

- `prd/<module>.md` is **WHAT** the module IS — target state. `## What users get` carries schema sketches / endpoint outlines / screen flows; `## Quality bar` carries user-visible NFRs.
- `impl/<module>/<update>/task_plan.md` is **HOW-overview** for one milestone of work on that module.
- `impl/<module>/<update>/tasks/p<n>_impl.md` is **HOW-detail** — DB migrations, API code, file diffs per phase.

**Two test tiers** (not interchangeable):

- `e2e/` — **permanent regression**. Lives as long as the PRD capability lives. Auto-discovered by pytest's default `test_*.py` glob; jest/vitest projects need to add `testMatch: ['**/test_*.ts']` since their default `*.test.ts` glob skips `test_<capability>.ts` filenames. Runs in CI on every commit. Gates milestone close.
- `impl/<m>/<u>/tests/` — **milestone-scoped phase tests**. Committed with the update, can be archived when the milestone closes. NOT auto-discovered — invoked by explicit path. The `phase_*` prefix is chosen specifically to dodge default test-runner globs.

**No active-state file.** Hooks resolve the active update by mtime scan of `docs/super-manus/impl/<module>/*/`. One project = one PRD; the "feature" abstraction from older versions is gone.

**No changelog markers anywhere in PRD.** PRD is a current-state snapshot. History lives in `git log` and per-update `findings.md`.

## How `prd-update` works (two modes, identical options)

Same 5 options, two different trigger contexts. The command auto-detects mode from `prd_drift.md`:

| `prd_drift.md` has a pending row for `<module>`? | Mode | Used for |
|---|---|---|
| No | **Forward iteration** | Adding/refining a capability *before* code is written |
| Yes | **Drift absorption** | PRD catches up to code that already deviated |

Mode is invisible at the call site — same command, same 5 options. What differs is the side effects:

| Action | Forward | Drift |
|---|---|---|
| Edits `prd/<module>.md` (single bullet, single section) | ✅ | ✅ |
| Writes a 3-line Decision into the active update's `findings.md ## Decisions` | — | ✅ |
| Flips matching `prd_drift.md` row: `Resolution = pending` → `prd-update: <a-e>` | — | ✅ |
| Touches `progress.md` | — (hook-managed only) | — (hook-managed only) |
| Closing message | "Run `/super-manus:sync <module>` to scaffold the milestone." | "Drift row resolved. Resume the update." |

For **Tighten / Demote / Split**, the command runs the [drift check protocol](skills/using-sm/SKILL.md) (LSP + grep, double-source) on the affected bullet *before* writing — so a "tighten" claim is verified to actually match what the code does today, not just what the user remembers. **Add** and **Exclude** skip verification (Add declares new intent; Exclude removes scope).

It will refuse and redirect in four cases:

| Situation | Suggestion |
|---|---|
| Edit crosses >1 section of `prd/<module>.md` | `/super-manus:brainstorm` (full rewrite path) |
| Deviation is purely tech-design (e.g. "we used Redis not Postgres") | Don't move PRD — log it as a Decision in the active update's `findings.md` only |
| PRD already matches reality (no actual conflict) | Stop, don't invent an edit |
| Edit would push `prd/<module>.md` past 2000 words | `/super-manus:brainstorm` — module outgrew a single PRD |

The tech-design refusal is the most common one in practice. PRD is product semantics — schema sketches at "table X has fields a, b, c" level are fine, but library names, file paths, line numbers, and code identifiers are not. If a "drift" is really "we picked a different DB", that's an `## Approach` decision in `tasks/p<n>_impl.md`, not a PRD movement.

`prd-update` is the tool you reach for when PRD needs to move. The next section explains the system that decides *when* PRD might need to move — and prevents the agent from moving it silently.

## Drift detection

The cardinal rule of super-manus: **the agent never silently updates PRD**. When PRD and code disagree, the disagreement is logged to `prd_drift.md` and surfaced to you — you decide whether code retreats or PRD advances.

### What counts as drift

| Direction | Example | Term |
|---|---|---|
| Code adds a capability PRD didn't promise | Implementation exposes `GET /metrics`, PRD has no observability bullet | **over-shoot** |
| Code lacks a capability PRD promised | PRD says "SSO supported", code has no SSO path | **under-shoot** |
| Code violates a `## Quality bar` constraint | PRD says p99 < 200ms, observed p99 is 5s | **quality violation** |
| Code crosses a `## Out of scope` line | PRD excludes mobile, repo gains a React Native entry | **out-of-scope crossing** |

Pipeline-violation rows also land in `prd_drift.md` and behave the same way: `code-writer modified tests for phase p<n>` (cheat-prevention hash mismatch), `test-writer touched non-test files`, `missing e2e coverage for capability <c>`, and `e2e for capability <c> is red`. They count toward the gate's `pending` total and block roadmap → `stable` until resolved.

### When detection runs

Not a daemon — it runs on six command paths (anchored in [skills/using-sm/SKILL.md §4 Per-command application](skills/using-sm/SKILL.md)):

| Trigger | Compares |
|---|---|
| `/super-manus:reverse-prd` | Inferred PRD claims vs current code (initial bootstrap) |
| `/super-manus:sync <module>` | The new milestone's stated intent vs the module's current PRD |
| `/super-manus:prd-update` (Tighten / Demote / Split) | The narrowed/demoted/split bullet vs current code (verification before write) |
| `/super-manus:impl` (phase entry) | The phase's `## Objective` vs PRD `## What users get` / `## Quality bar` / `## Out of scope` |
| `/super-manus:drive` | PRD + roadmap + recent commit-message hints (lightweight pre-action sweep) |
| End-of-update gate (3 passes) | Pass 1 refresh from commits / Pass 2 e2e coverage / Pass 3 `pending` count must be 0 |

### How detection works

The protocol (see [skills/using-sm/SKILL.md §4](skills/using-sm/SKILL.md)) uses two tools that answer different questions:

- **LSP** (`workspace_symbols`, `document_symbols`, `find_references`) — structural truth: does the symbol PRD claims actually exist in the indexed code?
- **grep + Read** — textual signals: TODO markers, route paths, config files, license clauses, anything LSP doesn't index.

The **double-source rule**: a drift verdict requires both signals to agree **when both apply** (some inference targets — Quality bar, Risks, product intent — are grep- or Read-only by nature; LSP simply doesn't apply). Single-source claims become `(audit)` markers — either inline in `prd/<module>.md` or under `## Open questions` — not drift rows. Budget per check: ≤10 LSP calls + ≤30 grep/Read calls; over-budget → stop and report, no exhaustive sweeps.

LSP unavailable (cold project, polyglot repo, missing toolchain) → grep-only mode, every verdict tagged `(audit)`.

### What happens when drift is found

```
detected
   ↓
append one row to prd_drift.md (Resolution = pending)
   ↓
agent stops, presents three resolution paths:
   1. /super-manus:prd-update <m>      — PRD advances to code (drift mode flips Resolution → prd-update: <a-e>)
   2. git revert <commit> + edit row   — code retreats to PRD; manually set Resolution = reverted with a one-line note in findings.md
   3. write the missing e2e + re-run   — for Pass 2 "missing/red e2e" rows, the gate clears the row when the e2e is added and goes green
   ↓
you decide. agent never silently moves PRD.
   ↓
end-of-update gate refuses to flip roadmap → stable
while any pending row exists for the module
```

The `prd_drift.md` file is **row-append-only** — only the Resolution cell is mutable; rows themselves are never deleted or reordered. This is the same mechanism that keeps the implementing agent honest — no silent overrides, every disagreement on the record.

## Self-sufficient execution discipline

super-manus does not depend on any other workflow plugin. The execution layer is built in:

- **`impl-reviewer` agent + 3 review checkpoints (v0.7)** — read-only agent at three points in the impl pipeline:
  - **`pre-test`** (after architect, before test-writer) — verifies plan claims against external reality (`head -1` on declared inputs, `(audit)` markers resolved, every declared input has a `## Verification` smoke).
  - **`pre-code`** (after test-writer, before code-writer) — verifies fixtures use real-data samples (not inline dicts derived from architect's plan), tests cover all declared inputs, tests are red as expected, and tests pass project-configured type-check (skipped if no config).
  - **`pre-close`** (after code-writer, before verification) — verifies impl matches `## Approach`, touched files are subset of `## Files touched`, no security smell. If code-writer reported stuck ("tests un-passable"), reviewer diagnoses whether test, plan, or code is the root cause.
  
  Verdicts: **APPROVE** / **RETURN_TO_<writer>** / **ESCALATE_TO_USER**. RETURN can target any upstream writer — `pre-close` may RETURN_TO_TEST_WRITER if the failing test fixture is wrong, or RETURN_TO_ARCHITECT if the plan turned out wrong. The orchestrator cascades — re-spawns the target writer + every downstream stage, refreshes the hash baseline on test re-commit, then re-invokes the originating review. Per-checkpoint retry budget: max 2 RETURNs per checkpoint; 3rd RETURN escalates to user with full feedback history. Reviewer is **read-only by tool surface** (no `Write`, no `Edit`) — cheat-prevention boundary preserved.

- **`tdd-in-phases`** — the test-writer is spawned BEFORE the code-writer (non-negotiable). Phase tests + e2e tests are committed red; code-writer flips them green and is forbidden from editing tests. Three independent barriers prevent the implementing agent from gaming its own tests:
  - **Time** — tests are in git before code-writer is spawned.
  - **Write permission** — code-writer's persona forbids editing tests; orchestrator hashes test files (after `pre-code` review APPROVE) and re-hashes after code-writer, aborts on tamper.
  - **Persona** — test-writer anchors tests in PRD `## What users get` / `## Quality bar` / `## Risks` and `_index.md ## Demo` (cross-module scenarios → `e2e/_system/`), treating `## Approach` as one of many valid impls.
- **`verification-before-phase-close`** — phase Status flips to `closed` only after every command in `tasks/p<n>_impl.md ## Verification` exits green. Verification MUST include (1) the phase test path command and (2) one user-visible smoke command.
- **`systematic-debugging-in-phase`** — when verify fails, follow the checklist (re-read Approach, re-read failing test, binary-search the diff, write a regression test, then fix). Three strikes against the same error class → escalate.

If you previously ran super-manus alongside `obra/superpowers`, you no longer need to. v0.5+ absorbs the three pieces that fit the PRD-led loop (TDD / verification / systematic debugging); the rest is either redundant or orthogonal.

## Doesn't do

Out of scope on purpose:

- Module rename command (manual: rename folders + edit `prd/_index.md`)
- Multi-product monorepo support in one super-manus folder (use multiple super-manus-enabled subdirectories)
- Auto-promote phase test → e2e (manual: move + rename)
- Retroactive e2e backfill for v0.4 projects (write yourself, or wait until a future phase touches the capability)
- Multi-harness orchestration / PR creation / merge integration
- Test framework / runner — super-manus invokes whatever your project already uses (`pytest`, `npm test`, `cargo test`, `go test`, your `Makefile` targets); it does not impose one

## Updates

The plugin manifest at `.claude-plugin/plugin.json` is the canonical version source. Each version below links to its design doc.

### v0.7.0 — current

Adds the **`impl-reviewer` agent** at three checkpoints (`pre-test` / `pre-code` / `pre-close`) inside `/super-manus:impl` and `/super-manus:impl-all`. Read-only by tool surface (no `Write`, no `Edit`); drives a re-spawn loop with per-checkpoint retry budget (max 2 RETURNs per checkpoint; 3rd RETURN escalates to user with full history). Verdicts: `APPROVE` / `RETURN_TO_<writer>` / `ESCALATE_TO_USER`. RETURN can target any upstream writer — `pre-close` reviewer can RETURN_TO_TEST_WRITER if the failing test fixture is wrong, or RETURN_TO_ARCHITECT if the plan turned out wrong only on impl. Cheat-prevention preserved: hash baseline is established AFTER `pre-code` review APPROVE — never before.

Why: a May 2026 dogfood case (multi-source parser) exposed two structural gaps in v0.6's 3-agent linear trust chain — plan-time fabrication (architect cited field names without `head -1` verification; 5/6 sources silently dropped in production) and test-side dead-end (when phase tests are wrong, code-writer can't edit them and the v0.6 escape hatch was conceptually documented but mechanically unwired). The reviewer breaks the trust chain by injecting external reality (head -1 on declared inputs, project-configured type-check, code-vs-plan diff verification) and by giving the loop a clean RETURN-with-feedback path that doesn't break the hash baseline.

See [docs/design-v0.7.md](docs/design-v0.7.md). Plugin manifest bumped to 0.7.0; pure additive vs v0.6 (no path migration, no PRD-schema changes, no test-fixture changes).

### v0.6.1

Fix in `impl-architect`: phase tests are now always declared under `${update_dir}/tests/phase_p<n>_*.<ext>` instead of co-opting the project's existing test suite (`apps/<m>/tests/`, `docs/super-manus/e2e/`). Matching test invariants in `tests/test_agent_impl_architect.sh`. Pure agent-guidance + template fix; no path migration.

### v0.6.0 — prd-update dual-mode

`/super-manus:prd-update` covers both modes — forward iteration ("add a new bullet before coding") and drift absorption (resolve a pending `prd_drift.md` row). Mode is auto-detected from `prd_drift.md` state. Plus a docs sweep. Everything from v0.5 stays. See [docs/design-v0.6.md](docs/design-v0.6.md).

### v0.5 — self-sufficient execution + e2e regression

Adds the **3-agent `/super-manus:impl` pipeline** (architect → test-writer → code-writer with time / write / persona barriers between test-writer and code-writer) and the **permanent e2e regression suite** at `docs/super-manus/e2e/` mirroring PRD's module/_index structure. End-of-update drift gate gains **Pass 2 — e2e coverage check**: every touched `## What users get` capability needs a passing `e2e/<module>/test_<capability>.<ext>` or roadmap can't flip to `stable` (Pass 3 still gates on `pending == 0`). Three execution skills (`tdd-in-phases`, `verification-before-phase-close`, `systematic-debugging-in-phase`) ship with the plugin. Adds `/super-manus:impl-all`. See [docs/design-v0.5.md](docs/design-v0.5.md) (superseded).

### v0.4 — project-global PRD

Two-axis model — module × milestone — replaces the v0.2/v0.3 per-feature folder. PRD lives at `docs/super-manus/prd/` (one project = one PRD). Implementation is per-module per-milestone at `docs/super-manus/impl/<module>/<YYYY-MM-DD>-<update-name>/`. Drift gate (PRD ↔ implementation alignment) becomes BLOCKING. `.super-manus/active` pointer file gone — hooks resolve via mtime scan. See [docs/design-v0.4.md](docs/design-v0.4.md) (superseded).

### v0.2 / v0.1 — early versions

[docs/design-v0.2.md](docs/design-v0.2.md) and [docs/design-v0.1.md](docs/design-v0.1.md). Per-feature folder layout, `.super-manus/active` pointer file. Superseded; kept for historical reference.
