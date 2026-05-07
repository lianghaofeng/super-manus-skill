# super-manus

> 🌐 **Languages**: **English** · [简体中文](README.zh-CN.md)

A Claude Code plugin for **PRD-led, drift-aware development**. State lives on disk and survives `/clear` and `/compact`. Each milestone runs through a 3-agent TDD pipeline (architect → test-writer → code-writer); the implementing agent has no permission to edit its own tests. A blocking drift gate refuses to mark work "done" while the per-module PRD and the actual code disagree.

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
| `/super-manus:start` | once per project | Seeds `docs/super-manus/{prd,impl,e2e}/`, `roadmap.md`, `prd_drift.md`. |
| `/super-manus:brainstorm` | new project | 6-question PM interview → writes `prd/_index.md` + per-module `prd/<module>.md` stubs. |
| `/super-manus:reverse-prd` | existing project, no PRD yet | Reads code (runtime-first module discovery), writes `prd/_index.md` (with ASCII arch diagram) + module stubs. |
| `/super-manus:prd-update <module>` | adding a capability OR resolving drift | Structured 5-option edit on one `prd/<module>.md`: **add / tighten / split / demote / exclude**. Mode (forward iteration vs drift absorption) is auto-detected. |
| `/super-manus:sync <module>` | after a PRD edit | Reads `git diff prd/<module>.md`, drafts 3-6 candidate phases, scaffolds the milestone folder. |
| `/super-manus:impl` | iterate one phase | Runs ONE phase end-to-end (architect → test-writer → code-writer → verify → close), then stops. |
| `/super-manus:impl-all` | finish a milestone | Loops through ALL pending phases of the active update without pausing. Same pipeline + drift checks per phase. |
| `/super-manus:drive` | "what next?" | Reads everything, picks one of the above, announces decision + reason, executes. |
| `/super-manus:catchup` | new session | Re-injects PRD overview + active update's task_plan into context. |
| `/super-manus:log` | manual checkpoint | Append a session log entry to the active update's `progress.md` now. |

### `/super-manus:prd-update` — the five edit options

PRD edits are structured, not freeform. One bullet at a time:

| Option | Use when | Effect |
|---|---|---|
| **add** | a new capability | Append a bullet to `## What users get`. |
| **tighten** | a claim is too vague | Rewrite a bullet with sharper user-visible language + technical evidence. |
| **split** | one bullet covers two distinct capabilities | Replace one bullet with two, both individually auditable. |
| **demote** | a bullet was overpromised | Move it to `## Open questions`. |
| **exclude** | a bullet is no longer in scope | Move it to `## Out of scope`. |

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
#   - impl-test-writer commits red phase + e2e tests
#   - impl-code-writer writes src until tests green
#   - orchestrator runs ## Verification commands
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
    ├── e2e/                                    # permanent regression suite, mirrors prd/
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

- `e2e/` — **permanent regression**. Lives as long as the PRD capability lives. Auto-discovered by your project's test runner (pytest `test_*.py`, jest `*.test.ts`). Runs in CI on every commit. Gates milestone close.
- `impl/<m>/<u>/tests/` — **milestone-scoped phase tests**. Committed with the update, can be archived when the milestone closes. NOT auto-discovered — invoked by explicit path. The `phase_*` prefix is chosen specifically to dodge default test-runner globs.

**No active-state file.** Hooks resolve the active update by mtime scan of `docs/super-manus/impl/<module>/*/`. One project = one PRD; the "feature" abstraction from older versions is gone.

**No changelog markers anywhere in PRD.** PRD is a current-state snapshot. History lives in `git log` and per-update `findings.md`.

## Self-sufficient execution discipline

super-manus does not depend on any other workflow plugin. The execution layer is built in:

- **`tdd-in-phases`** — when `/super-manus:impl` enters a phase, the test-writer is spawned BEFORE the code-writer (non-negotiable). Phase tests + e2e tests are committed red; code-writer flips them green and is forbidden from editing tests. Three independent barriers prevent the implementing agent from gaming its own tests:
  - **Time** — tests are in git before code-writer is spawned.
  - **Write permission** — code-writer's persona forbids editing tests; orchestrator hashes test files before/after and aborts on tamper.
  - **Persona** — test-writer anchors tests in PRD `## What users get` / `## Quality bar` / `## Risks`, treating `## Approach` as one of many valid impls.
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

### v0.6.x — current

`/super-manus:prd-update` covers both modes — forward iteration ("add a new bullet before coding") and drift absorption (resolve a pending `prd_drift.md` row). Mode is auto-detected. Plus a docs sweep and a fix making `impl-architect` always declare phase tests under `${update_dir}/tests/` (instead of co-opting the project's existing test suite). Everything from v0.5 stays. See [docs/design-v0.6.md](docs/design-v0.6.md).

### v0.5 — self-sufficient execution + e2e regression

Adds the **3-agent `/super-manus:impl` pipeline** (architect → test-writer → code-writer with time / write / persona barriers between them) and the **permanent e2e regression suite** at `docs/super-manus/e2e/` mirroring PRD's module/_index structure. End-of-update drift gate gains Pass 3 — e2e coverage check: every touched `## What users get` capability needs a passing `e2e/<module>/test_<capability>.<ext>` or roadmap can't flip to `stable`. Three execution skills (`tdd-in-phases`, `verification-before-phase-close`, `systematic-debugging-in-phase`) ship with the plugin. Adds `/super-manus:impl-all`. See [docs/design-v0.5.md](docs/design-v0.5.md) (superseded).

### v0.4 — project-global PRD

Two-axis model — module × milestone — replaces the v0.2/v0.3 per-feature folder. PRD lives at `docs/super-manus/prd/` (one project = one PRD). Implementation is per-module per-milestone at `docs/super-manus/impl/<module>/<YYYY-MM-DD>-<update-name>/`. Drift gate (PRD ↔ implementation alignment) becomes BLOCKING. `.super-manus/active` pointer file gone — hooks resolve via mtime scan. See [docs/design-v0.4.md](docs/design-v0.4.md) (superseded).

### v0.2 / v0.1 — early versions

[docs/design-v0.2.md](docs/design-v0.2.md) and [docs/design-v0.1.md](docs/design-v0.1.md). Per-feature folder layout, `.super-manus/active` pointer file. Superseded; kept for historical reference.
