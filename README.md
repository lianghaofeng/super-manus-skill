# super-manus

> 🌐 **Languages**: **English** · [简体中文](README.zh-CN.md)

*PRD-led, drift-aware development for Claude Code. Survives `/clear`, generates dev-readable progress journals from git history. Self-sufficient — ships with its own TDD / verification / debugging discipline and a 3-agent impl pipeline that prevents the implementing agent from gaming its own tests.*

## What

**super-manus** is a Claude Code plugin for PRD-led, drift-aware development. It owns four things: (1) a project-global folder on disk holding your PRD, roadmap, drift log, and per-milestone implementation state; (2) hooks that keep them in sync as you commit; (3) a 3-agent `/super-manus:impl` pipeline (architect → test-writer → code-writer) with time / write / persona barriers between them; (4) a permanent e2e regression suite at `docs/super-manus/e2e/` that mirrors the PRD module structure and gates milestone close.

## Why

Single-shot LLM coding loses everything on `/clear` or `/compact`. Plan-first tools (Manus-style file-based state, [OthmanAdi/planning-with-files](https://github.com/OthmanAdi/planning-with-files)) keep state but don't enforce that code stays aligned with the spec. A single agent that writes both tests and impl has obvious motives to write weak tests, mirror the impl plan, or adjust expectations after seeing the impl. v0.5 super-manus targets all three: persistent project state across sessions, a BLOCKING drift gate that refuses to mark a milestone done while the per-module PRD and the actual code disagree, and a 3-agent impl pipeline whose temporal + write-permission + persona barriers close the obvious cheating modes.

It ships with its own thin execution discipline (TDD scoped to phases, mandatory verification before phase-close, systematic debugging when a phase stalls) so you can run it standalone — no other workflow plugin required.

## v0.5 — self-sufficient execution discipline + e2e regression suite

v0.5 keeps the v0.4 project-global PRD layout intact and adds two things on top: a 3-agent `/super-manus:impl` pipeline that closes the "agent games its own tests" cheating modes, and a permanent e2e regression suite at `docs/super-manus/e2e/` that mirrors the PRD's module/_index structure.

**3-agent /super-manus:impl pipeline.** Each phase runs three agents in series with explicit trust boundaries between them:

1. **`impl-architect`** drafts `tasks/p<n>_impl.md` (Objective / Approach / Files touched / Verification). No code, no tests. Reused unchanged from v0.4.
2. **`impl-test-writer`** writes phase tests at `docs/super-manus/impl/<m>/<u>/tests/phase_p<n>_*.<ext>` (always) and e2e tests at `docs/super-manus/e2e/<module>/test_<capability>.<ext>` (when this phase **completes** a `## What users get` capability) or `docs/super-manus/e2e/_system/test_<scenario>.<ext>` (when it completes a cross-module `## Demo` scenario). Commits red tests. Persona discipline: tests anchored in PRD spec, not mirrored from `## Approach`.
3. **`impl-code-writer`** writes implementation per `## Approach` + `## Files touched`, iterates until phase tests + touched e2e tests are green. Has no permission to edit `tests/` or `e2e/` (forbidden in persona); the orchestrator hashes test files before/after this agent runs and aborts the phase on tamper.

The split exists for one reason: **prevent the implementing agent from gaming its own tests**. Three independent mechanisms enforce this:

- **Time barrier** — test-writer commits red tests BEFORE code-writer runs. By the time code-writer is spawned, tests are in git; there is no "future impl" for tests to mirror.
- **Write barrier** — code-writer's persona forbids editing tests; orchestrator hashes test files before/after and aborts on mismatch.
- **Persona discipline** — test-writer explicitly anchors tests in `prd/<module>.md ## What users get` / `## Quality bar` / `## Risks`, treating `## Approach` as one of many valid impls and refusing to mirror it.

Read access is OPEN — both new agents read everything. The cheat-prevention is temporal + write-permission + persona, not read-permission.

**Two-tier test maintenance.** test-writer maintains both:

- **Phase tests** at `docs/super-manus/impl/<m>/<u>/tests/phase_p<n>_<verb>_<noun>.<ext>` — milestone proof, NOT auto-discovered by CI. Lifetime: as long as the milestone update folder exists.
- **e2e tests** at `docs/super-manus/e2e/<module>/test_<capability>.<ext>` and `docs/super-manus/e2e/_system/test_<scenario>.<ext>` — permanent regression mirroring PRD's structure, AUTO-DISCOVERED by default test runner globs (pytest `test_*.py`, jest `*.test.ts`). Lifetime: as long as the capability lives in PRD.

CI runs the e2e suite on every commit; phase tests are run only by `/super-manus:impl` during phase execution.

**Two impl commands:**

- `/super-manus:impl` — DOGFOOD default. Runs ONE phase end-to-end (architect → test-writer → code-writer → verify → close), then stops. If that was the last pending phase, runs the end-of-update drift gate. Use when you don't fully trust the plan yet, or want a natural git history of one phase per session.
- `/super-manus:impl-all` — POWER MODE. Loops through ALL pending phases of the active update without pausing. Same 3-agent pipeline + same drift checks per phase; the only difference is no pauses between phases. Aborting it (Ctrl-C, error, drift detected, tamper detected, gate failed) leaves on-disk state identical to running `/super-manus:impl` that many times — fallback is safe.

**End-of-update drift gate gains Pass 3 — e2e coverage check.** For every `## What users get` capability touched by this update's commits, `e2e/<module>/test_<capability>.<ext>` MUST exist AND pass. Missing or red → `pending` row in `prd_drift.md`, BLOCKS roadmap from flipping to `stable`.

See [docs/design-v0.6.md](docs/design-v0.6.md) for the current design. [docs/design-v0.5.md](docs/design-v0.5.md) (superseded), [docs/design-v0.4.md](docs/design-v0.4.md) (superseded), and [docs/design-v0.2.md](docs/design-v0.2.md) (superseded) are kept for historical reference.

### v0.4 — project-global PRD (still in place)

v0.5 keeps every v0.4 invariant. The v0.4 layout — project-global PRD with module × milestone two-axis model — is unchanged:

- **PRD is project-global** (`docs/super-manus/prd/`), one file per module (db / api / frontend / ...). Each per-module PRD allows schema sketches, interface outlines, UX flows in its `## What users get` section — the level of detail a PM gives engineering — capped at ~2000 words. Under that, nine stable headings (Why this exists / Users / Success / What users get / How it connects / Quality bar / Risks / Out of scope / Open questions). The project-level `prd/_index.md` adds Audience + Success metrics on top of Problem / Demo / Must / Not doing / Modules / Data flow overview.
- **Implementation is per-module per-milestone**: each "milestone update" is a folder under `docs/super-manus/impl/<module>/<YYYY-MM-DD>-<update-name>/` containing the four-file set (`task_plan.md`, `findings.md`, `progress.md`, `tasks/p<n>_impl.md`) plus the new v0.5 `tests/` subfolder. Old updates are immutable historical record; the latest is active. Timestamps appear ONLY here.
- **PRD ↔ implementation alignment is enforced**: when intent diverges from PRD, the agent stops, logs to `prd_drift.md`, and asks the user — revert implementation, or run `/super-manus:prd-update <module>`. PRD is never silently updated.
- **No active-state file.** The `.super-manus/active` pointer from v0.2/v0.3 is gone. Hooks resolve the active update purely by mtime scan of `docs/super-manus/impl/<module>/*/`. The "feature" abstraction is gone — there is one project = one PRD.

## Install

**Recommended — add the marketplace, then `/plugin` install:**

```
/plugin marketplace add https://github.com/lianghaofeng/super-manus-skill
/plugin install super-manus@super-manus-skill
```

You'll get future updates via `/plugin marketplace update super-manus-skill`.

**Local marketplace (for local development or if remote install fails):**

```
/plugin marketplace add /path/to/super-manus
/plugin install super-manus@super-manus-skill
```

Point at a local clone of this repo — `marketplace.json` lives at `.claude-plugin/marketplace.json` and resolves the plugin from the same checkout.

On first install, restart your Claude Code session so hooks and slash commands register.

## Quickstart (v0.4)

```
/super-manus:start                        # idempotently seeds docs/super-manus/{prd,impl}/,
                                          # roadmap.md, prd_drift.md (no arguments)
/super-manus:brainstorm                   # 6 questions (last = module split). Writes
                                          # docs/super-manus/prd/_index.md + per-module
                                          # prd/<module>.md stubs at not-started in roadmap
... user audits prd/<module>.md files, fleshes out ## What users get ...
/super-manus:sync <module>                # reads `git diff prd/<module>.md` to detect the new
                                          # capability you just added, spawns the sync-planner
                                          # agent to draft 3-6 candidate Phases (with (audit)
                                          # markers), scaffolds docs/super-manus/impl/<module>/
                                          # <date>-<name>/ with the four-file set + planner's
                                          # Phases; flips module to iterating
... user reviews task_plan.md Phases (planner-drafted, not blank) ...
/super-manus:impl                         # auto-finds next pending phase, runs drift check,
                                          # spawns the impl-architect agent to draft tasks/
                                          # p<n>_impl.md, then proceeds to write code +
                                          # commit. End-of-update: BLOCKING drift gate refuses
                                          # to mark the update done while prd_drift.md has
                                          # pending rows for the module.
git commit -m "..."                       # post-commit hook prompts agent to log into the active
                                          # update's progress.md
/clear                                    # safe — state is on disk
... next session ...                      # SessionStart hook injects prd/_index.md + the active
                                          # update's task_plan
```

When PRD and implementation diverge:

```
/super-manus:prd-update <module>          # structured edit on a single per-module PRD (5 options:
                                          # tighten / split / demote / exclude / add). Two modes:
                                          # - forward iteration (add a new bullet before coding)
                                          # - drift absorption (resolve a pending prd_drift row)
                                          # mode is auto-detected from prd_drift.md.
/super-manus:sync <module>                # PRD changed — scaffold a new update folder for that module
```

When you don't know what to do next, use the global switch:

```
/super-manus:drive                        # reads everything, picks one of brainstorm / sync /
                                          # prd-update / impl, announces decision + reason, executes
```

For an existing project that has no PRD yet:

```
/super-manus:reverse-prd                  # one-shot: orchestrator does runtime-first module
                                          # discovery (compose / Makefile / apps / scripts),
                                          # then spawns the reverse-prd-architect agent (chief
                                          # architect + senior PM persona) which writes
                                          # docs/super-manus/prd/_index.md (with a mandatory
                                          # ASCII architecture diagram) + per-module stubs.
                                          # Audit (audit) markers afterwards, then sync per module.
```

**Two-axis model** (no overlap):

- `prd/<module>.md` is **WHAT** the module IS (target state). `## What users get` carries schema sketches / endpoint outlines / screen flows; `## Quality bar` carries user-visible NFRs.
- `impl/<module>/<update>/task_plan.md` is **HOW-overview** for ONE milestone of work on that module.
- `impl/<module>/<update>/tasks/p<n>_impl.md` is **HOW-detail** — DB migrations, API code, file diffs per phase.

PRD edits in v0.4 follow two paths:

- **Normal iteration**: edit `prd/<module>.md` directly (add a `## What users get` bullet, tighten `## Quality bar`), then run `/super-manus:sync <module>` — sync v2 reads the git diff and drafts Phases for the new capability automatically.
- **Forward iteration via `/super-manus:prd-update <module>`** (v0.6+): want to add a new `## What users get` bullet or tighten an existing one without leaving the slash-command flow? `prd-update` now handles forward edits too. Mode is auto-detected: if no pending `prd_drift.md` row matches the module, the command prompts for the new intent and runs the same 5-option edit. After landing, run `/super-manus:sync <module>` to scaffold the milestone.
- **Surgical drift absorption**: when implementation has already deviated and you want PRD to move (rather than reverting code), use `/super-manus:prd-update <module>` — same command, drift mode kicks in automatically when a pending row exists. The active update's `findings.md` gets a paired Decision entry; `prd_drift.md` row's Resolution flips out of `pending`, unblocking the end-of-update drift gate.

Drift between PRD and implementation is always logged to `prd_drift.md` (append-only) and resolved by the user. PRD files cap at ≤2000 words per module / ≤700 words for `_index.md`. No changelog markers anywhere — PRD is a current-state snapshot, history lives in `git log` and `findings.md`.

**Session log cadence** is unchanged — the Stop hook rate-limits checkpoints via `SUPER_MANUS_LOG_EVERY_N_TURNS` (default 5) and `SUPER_MANUS_LOG_MODE` (`both` / `turns` / `commit` / `off`); the agent judges whether to write each time. The state file lives inside the active update folder, so per-update turn counts are isolated.

## Layout

The on-disk layout super-manus creates inside a project that uses it (v0.5):

```
<project-root>/
└── docs/super-manus/
    ├── prd/                                    # project-global, ONE source of truth
    │   ├── _index.md                           # project overview + module manifest + data flow (≤700 words)
    │   └── <module>.md                         # per-module target state (≤2000 words; /super-manus:prd-update)
    ├── e2e/                                    # NEW in v0.5: permanent regression, mirrors prd/
    │   ├── _system/                            # cross-module scenarios from prd/_index.md ## Demo
    │   │   └── test_<scenario>.<ext>           # auto-discovered by test runner; runs in CI
    │   └── <module>/                           # per-module capabilities from prd/<module>.md ## What users get
    │       └── test_<capability>.<ext>         # auto-discovered by test runner; runs in CI
    ├── roadmap.md                              # project-global, module status table (auto-managed)
    ├── prd_drift.md                            # project-global, PRD ↔ implementation drift log (append-only)
    └── impl/                                   # time series of milestones, per module
        └── <module>/
            └── <YYYY-MM-DD>-<update-name>/     # only place timestamps appear
                ├── task_plan.md                # phase index for this update
                ├── findings.md                 # decisions / errors / data points for this update
                ├── progress.md                 # commits + session log for this update (hook-managed)
                ├── tasks/
                │   └── p<n>_impl.md            # per-phase technical plan (lazy, /super-manus:impl)
                └── tests/                      # NEW in v0.5: phase tests, milestone-scoped, NOT auto-discovered
                    └── phase_p<n>_<verb>_<noun>.<ext>
```

The two test directories are not interchangeable. `e2e/` is **permanent regression** (lives as long as the PRD capability lives, auto-discovered by CI). `impl/<m>/<u>/tests/` is **milestone-scoped phase tests** (committed with the update, can be archived when the milestone closes, NOT auto-discovered — invoked by explicit path).

## What it does NOT do

v0.5 stays small. Out of scope:

- Module rename command (low frequency — rename folders + edit `prd/_index.md` manually)
- Migration command from v0.2/v0.3 (manual: move files per the using-sm skill §8)
- Multi-product monorepo support in a single super-manus folder (use multiple super-manus-enabled subdirectories — one per product — or stay on v0.3)
- Code review skill / agent — deferred (`## Verification` + 3-pass drift gate covers the load-bearing checks)
- Auto-promote phase test to e2e suite (manual move + rename per the naming convention)
- Retroactive e2e-coverage backfill for v0.4 projects (write e2e for old capabilities yourself, or wait until a future phase touches that capability and the test-writer adds e2e then)
- Strict no-read isolation between test-writer and code-writer (open-read + write-barrier + persona-discipline path; revisit if cheating data justifies tightening)
- Multi-harness orchestration / PR creation / merge integration
- Test framework / runner — super-manus invokes whatever your project already uses (`pytest`, `npm test`, `cargo test`, `go test`, your `Makefile` targets, etc.); it does not impose one

## Self-sufficient execution discipline (v0.5)

super-manus does not depend on any other workflow plugin. It ships its own thin execution layer:

- **`tdd-in-phases` skill** — when `/super-manus:impl` enters a phase, the test-writer is spawned BEFORE the code-writer (non-negotiable). Phase tests go to `docs/super-manus/impl/<m>/<u>/tests/phase_p<n>_<verb>_<noun>.<ext>`; e2e tests go to `docs/super-manus/e2e/<module>/test_<capability>.<ext>` when the phase completes a capability. Test-writer commits red; code-writer flips green and is forbidden from editing tests.
- **`verification-before-phase-close` skill** — phase Status flips to `closed` only after every command in `tasks/p<n>_impl.md ## Verification` exits green. The orchestrator (not the code-writer) runs them. `## Verification` MUST include the path to phase tests for the phase plus one user-visible smoke command (curl an endpoint, run a CLI, open a page).
- **`systematic-debugging-in-phase` skill** — when a verify command fails, follow a checklist (re-read Approach, re-read failing test, binary-search the diff, write a regression test, then fix) instead of randomly trying things. Three strikes against the same error class → escalate.
- **3-agent `/super-manus:impl` pipeline** — `impl-architect` (drafts the phase plan), `impl-test-writer` (writes phase + e2e tests, red), `impl-code-writer` (writes implementation, green). The split replaces v0.4's single `impl-executor`. Time barrier (test-writer commits before code-writer runs) + write barrier (code-writer cannot edit tests; orchestrator hashes test files before/after) + persona discipline (test-writer anchors tests in PRD spec, not impl plan) close the obvious cheating modes.

If you previously ran super-manus alongside `obra/superpowers`, you no longer need to. v0.5 absorbs the three pieces of superpowers that actually fit the PRD-led loop (TDD / verify-before-completion / systematic debugging); the rest of superpowers either duplicated super-manus features (brainstorming, plan writing, plan execution, subagent dispatch) or was orthogonal (git worktrees, finishing branches). superpowers can stay installed for non-super-manus work, or you can uninstall it.

## Status

v0.6 — additive change on top of v0.5: `/super-manus:prd-update` now handles both forward iteration ("add a new bullet before coding") and drift absorption (resolve a pending `prd_drift.md` row). Mode is auto-detected. Everything else from v0.5 (3-agent impl pipeline, e2e regression suite, three execution skills, `/super-manus:impl-all`) is unchanged. See [docs/design-v0.6.md](docs/design-v0.6.md) for the current design. [docs/design-v0.5.md](docs/design-v0.5.md) (superseded), [docs/design-v0.4.md](docs/design-v0.4.md) (superseded), [docs/design-v0.2.md](docs/design-v0.2.md) (superseded), and [docs/design-v0.1.md](docs/design-v0.1.md) (superseded) are kept for historical reference.
