# Contributor Guide

This file is for AI agents (and humans) modifying the super-manus plugin itself. Read it before editing.

## Repo invariants

- Any change touching `hooks/` requires a matching `tests/test_<name>.sh`. New hook, new test — no exceptions.
- Same rule for `agents/`: each agent under `agents/<name>.md` needs `tests/test_agent_<name>.sh` asserting its frontmatter (name/description/tools), persona, inputs, and any behavioural invariants its callers rely on. Agents are spawned by slash commands via the Agent tool with `subagent_type=<name>`, so the agent's `name` frontmatter and the orchestrator's `subagent_type` must stay in lock-step.
- **Agent invariants (v0.5).** The two new impl agents — `impl-test-writer` and `impl-code-writer` — both need `tests/test_agent_<name>.sh` per the rule above. Their tests MUST also assert the write-barrier discipline: `impl-test-writer`'s persona says "tests anchored in PRD spec, NOT mirror of impl plan" and the agent has no `Edit` tool; `impl-code-writer`'s persona explicitly forbids editing any file under `tests/` or `e2e/` (the orchestrator additionally hashes test files before/after to enforce mechanically). If the persona text or the Tools frontmatter drifts, the test must catch it — these are the load-bearing v0.5 cheat-prevention boundaries.
- **Skill invariants (v0.5).** Each skill is a directory `skills/<name>/SKILL.md`. The four v0.5 skills — `using-sm`, `tdd-in-phases`, `verification-before-phase-close`, `systematic-debugging-in-phase` — each need `tests/test_skill_<name>.sh` (mirroring how `test_skill_using_sm.sh` covers `using-sm`). Skills are loaded by slash commands; the test asserts the SKILL.md frontmatter (`name`, `description`, `user-invocable`) plus any load-bearing section headings the orchestrator references.
- Templates under `templates/` must keep their schema headings verbatim. The full set in v0.2:
  - `task_plan.md`: `## Goal`, `## Phases`
  - `findings.md`: `## Decisions`, `## Errors`, `## Data points / research`
  - `progress.md`: `## Completed commits`, `## Session log`, `## Outstanding`
  - `phase_plan.md`: `## Objective`, `## Approach`, `## Files touched`, `## Verification`
  - `prd_index.md` (v0.2 PM-flavored, **8 H2 sections**): `## Problem`, `## Audience`, `## Success metrics`, `## Demo`, `## Must`, `## Not doing`, `## Modules`, `## Data flow overview`
  - `prd_module.md` (v0.2 PM-flavored, **9 H2 sections**): `## Why this exists`, `## Users`, `## Success`, `## What users get`, `## How it connects`, `## Quality bar`, `## Risks`, `## Out of scope`, `## Open questions`
  - **Schema migration note**: the previous v0.2 used 6-section technical headings (Purpose / Surface / Data flow / Constraints / Out of scope / Open questions on per-module; Problem / Demo / Must / Not doing / Modules / Data flow overview on `_index.md`). The PM-flavored set above replaces it everywhere — parsers, tests, agents, slash commands — there is no dual-mode acceptance.
  - `roadmap.md` (v0.2): `## Modules`
  - `prd_drift.md` (v0.2): `# PRD drift log` (single H1; the table is the body)
  - These headings are parsed by hooks and scripts; renaming them silently breaks the runtime.
- v0.1 templates (`templates/prd.md` — the flat-folder PRD) are kept for legacy v0.1 features and must not be removed; v0.2/v0.4 use `prd_index.md` + `prd_module.md` instead.
- Plugin manifest (`.claude-plugin/plugin.json`) and hook configuration (`hooks/hooks.json`) are load-bearing. Validate JSON before committing.

## v0.4 layout (PROJECT-GLOBAL PRD; current target)

The v0.3 layout wrapped everything in a per-feature timestamped folder (`docs/super-manus/<YYYY-MM-DD>-<feature>/`) which conflated two concepts: the PRD (a current-state snapshot of the project) and the impl time-series (per-update milestones). v0.4 separates them:

```
docs/super-manus/
├── prd/                                     ← project-global, ONE source of truth
│   ├── _index.md                            ← 8 PM-flavored H2 sections
│   └── <module>.md                          ← 9 PM-flavored H2 sections
├── roadmap.md                               ← project-global, module status table
├── prd_drift.md                             ← project-global, append-only drift log
└── impl/                                    ← time series of milestones, per module
    └── <module>/
        └── <YYYY-MM-DD>-<update-name>/      ← only place timestamps appear
            ├── task_plan.md
            ├── findings.md
            ├── progress.md
            └── tasks/
                └── p<n>_impl.md
```

Invariants:
- PRD files are **target state** (current snapshot, no changelog markers).
- `impl/<module>/<update>/` is the **time series**; old updates are immutable historical record.
- There is NO `.super-manus/active` state file in v0.4. Hooks resolve the active update purely via `sm_active_update` (mtime scan of `docs/super-manus/impl/<module>/*/`) — never invent a second active-state file.
- Drift between PRD and implementation is **always** logged to `prd_drift.md`; the agent must not silently update PRD.
- The "feature" abstraction is gone. There is one project = one PRD. Multi-product monorepos must use multiple super-manus-enabled subdirectories (one per product) or stay on v0.3.

### v0.5 layout deltas (additive on top of v0.4)

v0.5 keeps every v0.4 path. It adds two new directories:

```
docs/super-manus/
├── prd/                                     ← unchanged from v0.4
├── e2e/                                     ← NEW in v0.5: permanent regression, mirrors prd/
│   ├── _system/                             ← cross-module scenarios from prd/_index.md ## Demo
│   │   └── test_<scenario>.<ext>            ← auto-discovered by test runner; runs in CI
│   └── <module>/                            ← per-module capability tests from prd/<module>.md ## What users get
│       └── test_<capability>.<ext>          ← auto-discovered by test runner; runs in CI
├── roadmap.md                               ← unchanged
├── prd_drift.md                             ← unchanged
└── impl/<module>/<YYYY-MM-DD>-<update-name>/
    ├── task_plan.md                         ← unchanged
    ├── findings.md                          ← unchanged
    ├── progress.md                          ← unchanged
    ├── tasks/p<n>_impl.md                   ← unchanged
    └── tests/                               ← NEW in v0.5: phase tests, milestone-scoped
        ├── phase_p1_<verb>_<noun>.py            (Python)
        ├── phase_p2_<verb>_<noun>.phase.ts      (Node/TS)
        └── ...
```

Naming-convention invariants (parsed by orchestrator and tests):

- **Phase tests** live at `docs/super-manus/impl/<module>/<update>/tests/` and use `phase_p<n>_<verb>_<noun>.<ext>`. The `phase_*` prefix (Python) or `*.phase.ts` suffix (Node/TS) is chosen specifically so default test runner globs (`pytest test_*.py`, `jest *.test.ts`) DO NOT pick them up — phase tests are NOT auto-discovered by CI; they are run only by `/super-manus:impl` during phase execution via explicit path.
- **e2e tests** live at `docs/super-manus/e2e/<module>/test_<capability>.<ext>` (per-module capability) or `docs/super-manus/e2e/_system/test_<scenario>.<ext>` (cross-module scenario from `prd/_index.md ## Demo`). The `test_*` / `*.test.*` form IS auto-discovered by default runners — e2e tests are the permanent regression suite and CI runs them on every commit.

Two permanence tiers:

- Phase tests are committed with the milestone, archive when `roadmap.md` flips to `stable`, and may be deleted with the update folder. They prove "this phase shipped".
- e2e tests live as long as their PRD capability lives. They prove "this capability still works after future milestones". To promote a phase test to e2e, the user manually moves it to `e2e/<module>/` and renames per the convention above.

End-of-update drift gate gains **Pass 3 — e2e coverage check**: for every `## What users get` capability touched by this update's commits, `e2e/<module>/test_<capability>.<ext>` MUST exist AND pass. Missing or red → `pending` row in `prd_drift.md`, BLOCKS roadmap from flipping to `stable`.

The 3-agent `/super-manus:impl` orchestration (architect → test-writer → code-writer) replaces the v0.4 single `impl-executor`. The `impl-architect` agent is reused from v0.4 with no behavioural change; `impl-test-writer` and `impl-code-writer` are new. `/super-manus:impl-all` is a new command that loops the same 3-agent pipeline through all pending phases of the active update without pausing — useful when the plan is already audited.

## v0.3 → v0.4 path migration

| v0.3 path | v0.4 path |
| --- | --- |
| `docs/super-manus/<feature>/prd/_index.md` | `docs/super-manus/prd/_index.md` |
| `docs/super-manus/<feature>/prd/<module>.md` | `docs/super-manus/prd/<module>.md` |
| `docs/super-manus/<feature>/roadmap.md` | `docs/super-manus/roadmap.md` |
| `docs/super-manus/<feature>/prd_drift.md` | `docs/super-manus/prd_drift.md` |
| `docs/super-manus/<feature>/impl/<m>/<u>/` | `docs/super-manus/impl/<m>/<u>/` |
| `.super-manus/active` (feature folder name) | (removed; mtime resolve only) |

Slash command surface area also shrinks: `/super-manus:start` becomes a no-arg "enable in this project" command, `/super-manus:switch` is removed, `/super-manus:phase` (legacy v0.1) is removed. `/super-manus:catchup` re-injects the most-recently-modified update's task_plan plus the project-global `prd/_index.md`.

## PR governance

- Small commits, one logical change per commit.
- Commit messages follow the conventional style already in `git log` (`feat:`, `fix:`, `docs:`, `chore:`, `test:`).
- Never `git push --force` to `main`. If history needs rewriting, do it on a branch and open a PR.
- Run `bash tests/run-all.sh` before declaring any task done. A green run is the bar — not "looks right to me".
- Never commit `.DS_Store`, editor swap files, or anything outside the four-file commit you intended.

## Where to look

- **Current design** lives in `docs/design-v0.6.md` — source of truth for the v0.6 delta: repositioning `/super-manus:prd-update` to handle both forward iteration and drift absorption (mode auto-detected from `prd_drift.md`). Layout, agents, hooks, end-of-update drift gate are unchanged from v0.5.
- v0.5 design is preserved at `docs/design-v0.5.md` for historical reference (with a SUPERSEDED banner). v0.6 keeps everything in v0.5 (3-agent impl pipeline, e2e suite, three execution skills, `/super-manus:impl-all`) and only widens `/super-manus:prd-update`.
- v0.4 design is preserved at `docs/design-v0.4.md` for historical reference (with a SUPERSEDED banner). v0.4 is where the project-global PRD layout originated.
- v0.2/v0.3 design is preserved at `docs/design-v0.2.md` for historical reference (with a SUPERSEDED banner — its layout invariants no longer apply).
- v0.1 design is preserved at `docs/design-v0.1.md` for historical reference (with a SUPERSEDED banner).
- Plans (task-by-task implementation breakdown) live in `docs/plans/`.
- When in doubt about scope or layout, re-read `design-v0.6.md` before adding anything.
