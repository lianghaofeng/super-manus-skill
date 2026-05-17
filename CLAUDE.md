# Contributor Guide

This file is for AI agents (and humans) modifying the super-manus plugin itself. Read it before editing.

## Repo invariants

- Any change touching `hooks/` requires a matching `tests/test_<name>.sh`. New hook, new test — no exceptions.
- Each agent under `agents/<name>.md` needs `tests/test_agent_<name>.sh` asserting frontmatter (`name` / `description` / `tools` / `model` / `effort`), persona, inputs, and behavioural invariants its callers rely on. Agents are spawned via `subagent_type=<name>`, so the agent's `name` frontmatter and the orchestrator's `subagent_type` must stay in lock-step. The `model` field is `opus` for thinker agents (`impl-architect`, `impl-reviewer`, `reverse-architect` — renamed from `reverse-prd-architect` in v0.9.5 R9) and `inherit` for writer agents (`impl-test-writer`, `impl-code-writer`, `sync-planner`); `effort` is `max` for thinkers, `high` for writers — see `docs/design-v0.8.md §4` for the routing rationale and override priority chain.
- Each skill is a directory `skills/<name>/SKILL.md` and needs `tests/test_skill_<name>.sh` asserting the SKILL.md frontmatter (`name`, `description`) plus any load-bearing section headings the orchestrator references.
- `impl-test-writer` and `impl-code-writer` enforce the cheat-prevention boundary; their tests MUST assert the write barrier — `impl-test-writer` has no `Edit` tool; `impl-code-writer`'s persona forbids editing any file under `tests/` or `e2e/` (the orchestrator additionally hashes test files before/after to enforce mechanically).
- `scripts/probe-runtime.sh` is **read-only by contract**: it must never invoke `docker run/up`, `psql -c`, mutating `git` commands, or anything else that changes system state. `tests/test_probe_runtime.sh` enforces this with grep-based source-code checks. Any change adding mutating capabilities belongs in the orchestrator (under `AskUserQuestion` consent), not in the script.
- `templates/agents.yml` is the seed file for `.super-manus/agents.yml` (per-project per-agent `model:` override); seeded by `scripts/sm-start.sh`. The shipped template MUST have every override line commented — enabling super-manus on a fresh project must not silently change which model the user pays for. `tests/test_template_agents_yml.sh` enforces zero active overrides.
- Templates under `templates/` MUST keep their schema headings verbatim (parsed by hooks and scripts; renaming silently breaks the runtime):
  - `task_plan.md`: `## Goal`, `## Phases`
  - `findings.md`: `## Decisions`, `## Errors`, `## Data points / research`, `## Reflections` (orchestrator-appended at phase close)
  - `progress.md`: `## Completed commits`, `## Session log`, `## Outstanding`
  - `phase_plan.md` (5 H2, v0.9.0): `## Objective`, `## Approach`, `## Edge cases`, `## Files touched`, `## Verification`
  - `prd_index.md` (8 H2): `## Problem`, `## Audience`, `## Success metrics`, `## Demo`, `## Must`, `## Not doing`, `## Modules`, `## Data flow overview`
  - `prd_module.md` (9 H2): `## Why this exists`, `## Users`, `## Success`, `## What users get`, `## How it connects`, `## Quality bar`, `## Risks`, `## Out of scope`, `## Open questions`
  - `prd_spec.md` (4 H2, v0.9.5 R7): `## Data contracts`, `## Interface contracts`, `## Behavioral contracts`, `## Design rationale` (engineering voice; sibling to `prd_module.md`)
  - `roadmap.md`: `## Modules`
  - `drift_log.md` (v0.9.5 R10 — renamed from `prd_drift.md`; v0.9.7 R15 — Author column added between Date and Module): `# Drift log` (H1) + two H2 sections `## PRD drift` and `## Spec drift`, each carrying a 5-column `| Date | Author | Module | Conflict | Resolution |` table. Author cell is sourced from `git config user.name` at append time (falls back to `unknown` if unset).
  - `wiki_index.md` (v0.9.8 R16): `# Wiki index` (H1). Body is LLM-maintained — one H2 per topic file matching that topic file's H1, then a bulleted `- [<rule heading>](<topic>.md#<anchor>) — <one-line summary>` list. Regenerated from scratch by the orchestrator after every accepted promote.
  - `wiki_log.md` (v0.9.8 R16): `# Wiki log` (H1) + append-only `## [YYYY-MM-DD] <event> | <details>` H2 entries. Event types: `promote`, `promote-rejected`, `lint` (extend as new operations land). Grep prefix `^## \[` is the canonical "what happened recently" query. This log is the SOLE provenance record (no back-annotation on source `findings.md` entries).
- `.gitattributes` (v0.9.7 R13) is **narrowly scoped**: only `docs/super-manus/drift_log.md` and `docs/super-manus/roadmap.md` get `merge=union`. NEVER add `prd/*.md` or `prd/*.spec.md` rules — those are structured documents and union merge would silently keep contradictory edits to the same H2 section (Alice "200ms" + Bob "300ms" = both lines preserved, no conflict surfaced). `tests/test_gitattributes.sh` enforces the negative regression.
- `templates/codeowners.example` (v0.9.7 R14) is the canonical reference for GitHub CODEOWNERS routing per super-manus path conventions. Three sections: per-module ownership stanzas, cross-module shared files requiring multiple-team review, and inline-documented GitHub CODEOWNERS quirks (gitignore-style matching, same-org teams, last-match-wins). NOT auto-installed — users copy manually. `tests/test_template_codeowners.sh` enforces the three sections + ≥3 quirks documented.
- `templates/prd.md` (legacy v0.1 flat-folder PRD) is kept for backward compatibility and must not be removed.
- Plugin manifest (`.claude-plugin/plugin.json`) and hook configuration (`hooks/hooks.json`) are load-bearing. Validate JSON before committing.

## Layout

```
<project-root>/
├── .super-manus/                            ← static user preferences (committed)
│   └── agents.yml                           ← per-agent model override; seeded all-commented
└── docs/super-manus/                        ← business state (committed, reviewed in PR diffs)
    ├── prd/                                 ← project-global, ONE source of truth (PRD + spec siblings)
    │   ├── _index.md                        ← 8 PM-flavored H2 sections, target ~700 words of prose (soft cap; fenced code blocks and tables excluded)
    │   ├── <module>.md                      ← 9 PM-flavored H2 sections, target ~2000 words of prose (soft cap; fenced code blocks and tables excluded)
    │   └── <module>.spec.md                 ← v0.9.5 R7: 4-H2 engineering reference, sibling to <module>.md, target ~3000 words of prose (soft cap; fenced code blocks and tables excluded). Required per module — stateless modules use `(none — module is stateless)` placeholders.
    ├── e2e/                                 ← permanent regression suite, mirrors prd/
    │   ├── _system/test_<scenario>.<ext>    ← cross-module scenarios from prd/_index.md ## Demo
    │   └── <module>/test_<capability>.<ext> ← per-module capabilities from prd/<module>.md ## What users get
    ├── roadmap.md                           ← project-global, module status table
    ├── drift_log.md                         ← project-global, append-only drift log (v0.9.5 R10 — renamed from prd_drift.md; v0.9.7 R15 — Author column added). Two H2 sections: `## PRD drift` + `## Spec drift`. Same 5-column `| Date | Author | Module | Conflict | Resolution |` schema in each.
    ├── wiki/                                ← v0.9.8 R16: project-global engineering rules (cross-module conventions). The sole cross-update memory channel.
    │   ├── _index.md                        ← LLM-maintained catalog; regenerated from topic files after every accepted promote
    │   ├── _log.md                          ← append-only event log (`## [YYYY-MM-DD] <event> | <details>`)
    │   └── <topic>.md                       ← coarse-grained topic file (runtime.md, paths.md, testing.md, …). NOT seeded — first promote creates on demand.
    └── impl/<module>/<YYYY-MM-DD>-<update>/ ← time series of milestones (only place timestamps appear)
        ├── task_plan.md
        ├── findings.md
        ├── progress.md
        ├── tasks/p<n>_impl.md
        └── tests/phase_p<n>_<verb>_<noun>.<ext>  ← phase tests, milestone-scoped
```

Invariants:

- Project-global state lives at `docs/super-manus/prd/` (PRD + spec siblings), `docs/super-manus/roadmap.md`, `docs/super-manus/drift_log.md`, and `docs/super-manus/e2e/`. Per-update state lives at `docs/super-manus/impl/<module>/<YYYY-MM-DD>-<update>/`; phase tests live at `docs/super-manus/impl/<module>/<update>/tests/phase_p<n>_*.<ext>`.
- PRD files (`<module>.md` PM voice + `<module>.spec.md` engineering voice) are **target state** (current snapshot, no changelog markers). `git log -p prd/<module>.md` (or `git log -p prd/<module>.spec.md`) is the audit trail. The two views — PRD looks out at users, spec looks in at the system — must not contradict; same-topic overlap (e.g. PRD `## Quality bar` "signin returns within 200ms p95" vs spec `## Behavioral contracts` "Redis sliding-window rate-limit") is upstream/downstream, not duplication, and the `reverse-architect` emits a soft warning (not a drift row) when it spots overlap.
- `impl/<module>/<update>/` is the **time series**; old updates are immutable historical record.
- One project = one PRD. **`.super-manus/` (project-root, hidden) holds STATIC user preferences only**, currently just `agents.yml`. It MUST NOT hold dynamic runtime state — `.super-manus/active` is gone, no session cache, no resolved-paths file. Hooks resolve the active update via `sm_active_update` (mtime scan of `docs/super-manus/impl/<module>/*/`); never invent a second active-state file. The split between `.super-manus/` and `docs/super-manus/` is deliberate: the former is tool config set once; the latter is business state reviewed in PR diffs. Both are committed.
- Drift between PRD and implementation is **always** logged to `drift_log.md ## PRD drift`; drift between spec and implementation is **always** logged to `drift_log.md ## Spec drift` (v0.9.5 R10). The agent must not silently update PRD or spec.
- **Wiki vs spec decision tree** (v0.9.8 R16): when adding an engineering rule, pick the layer:
  1. Bound to a single module's data / interface / behavioral contract? → `prd/<module>.spec.md` (e.g. "POST /v1/signin returns 200ms p95", "auth uses Redis sliding-window for rate-limit")
  2. Project-wide convention spanning modules (language/runtime/tooling/process)? → `wiki/<topic>.md` (e.g. "Python 3.12 deprecated datetime.utcnow", "never fabricate metrics", "verify paths exist before writing")
  3. Multi-module but contract-shaped? → spec of the most-relevant module + a `wiki/<topic>.md` cross-reference (e.g. "all rate-limit middleware uses Redis SETEX with 1-minute window")
  Mnemonic: spec answers "what THIS module does", wiki answers "how WE write code in this project". Wiki entries land via reviewer `wiki-candidates:` flag at pre-close → user `AskUserQuestion` accept (see Architecture). The wiki `_log.md` is the sole provenance record; no annotation on source `findings.md` entries.
- **Phase tests** (`tests/phase_p<n>_*.<ext>` or `*.phase.ts`) are NOT auto-discovered by default test runners — `/super-manus:impl` runs them via explicit path. Naming chosen specifically to dodge `pytest test_*.py` / `jest *.test.ts` globs.
- **e2e tests** (`e2e/<module>/test_<capability>.<ext>`, `e2e/_system/test_<scenario>.<ext>`) ARE auto-discovered. They are the permanent regression suite; CI runs them on every commit.
- End-of-update drift gate is BLOCKING with 3 passes: refresh drift from commits + missing-spec.md detection (Pass 1, v0.9.5 R10 extension) / e2e coverage check (every touched `## What users get` capability has a passing e2e) / pending == 0 across BOTH `## PRD drift` and `## Spec drift` sections of `drift_log.md`. Missing or red e2e → `pending` row → blocks roadmap from flipping to `stable`. Missing `<module>.spec.md` → `pending` row in `## Spec drift` → blocks the same way.

## Architecture

- `/super-manus:impl` runs ONE phase through 4 agents with 3 review checkpoints: **impl-architect** (drafts `tasks/p<n>_impl.md`) → **impl-reviewer** [pre-test] → **impl-test-writer** (commits red phase tests + e2e) → **impl-reviewer** [pre-code] → **impl-code-writer** (writes source until tests green) → **impl-reviewer** [pre-close]. Reviewer is read-only by tool surface (no Write/Edit) and drives re-spawn loops; APPROVE / RETURN_TO_<writer> / ESCALATE_TO_USER per checkpoint, retry budget = 2 RETURNs (3rd ESCALATEs). Hash baseline for cheat-prevention is established AFTER review #2 APPROVE — never before — so cascade re-spawns (review #3 → test-writer) can re-hash on the new test commit.
- **Cross-phase memory** — at each phase close (after review #3 APPROVE + Verification pass), the orchestrator main thread synthesizes a 3-bullet `### p<n>: <name>` entry into `findings.md ## Reflections` when the phase had ≥1 reviewer RETURN event. The next phase's `impl-architect` / `impl-test-writer` spawns include the current update's `## Reflections` section verbatim as `<update_reflections>` (loaded via `sm_load_update_reflections`); writers honor `Heuristic:` lines as checklist items. **Same-update only** (v0.9.8 R17 simplification — previously cross-update via `sm_collect_reflections` with keyword filter): cross-update memory now flows exclusively through the wiki layer (see below); module-local lore that doesn't graduate to wiki is allowed to fade at update boundaries. Orchestrator-written so reviewer stays read-only.
- **Wiki layer (v0.9.8 R16-R19)** — `docs/super-manus/wiki/` is project-global engineering rules (cross-module conventions; see Wiki vs spec decision tree above). `sm_load_wiki "$phase_name"` (in `hooks/lib.sh`) returns `_index.md` verbatim + keyword-filtered topic files; the result is injected as `<wiki>` fact block into impl-architect Pass 2 / impl-test-writer / impl-code-writer / impl-reviewer (all 3 checkpoints). Writers honor wiki; reviewer enforces (wiki violation = `RETURN_TO_<writer>`). Wiki is explicitly NOT injected into architect Pass 1, sync-planner, or reverse-architect. Ingest: reviewer at pre-close optionally emits a `wiki-candidates:` YAML block; orchestrator runs `AskUserQuestion` per candidate; on accept the rule appends to `wiki/<topic>.md`, `_index.md` regenerates, `_log.md` gets a `promote` entry carrying source findings path + phase heading. No annotation on source findings — `wiki/_log.md` is the sole provenance record. Maintenance: `/super-manus:wiki-lint` (manual or as end-of-update drift gate Pass 4, non-blocking) runs five checks — contradiction / stale / orphan / gap / cross-ref miss — and writes findings to `wiki/_log.md`.
- `/super-manus:impl-all` loops the same pipeline through all pending phases without pausing; loop-stops include reviewer ESCALATE_TO_USER.
- `/super-manus:prd-update <module>` is dual-mode: forward iteration (no pending drift row → user adds/tightens a bullet before coding; skip findings.md write) or drift absorption (pending row → write findings.md decision + flip Resolution). Mode auto-detected.
- `/super-manus:spec-update <module>` (v0.9.5 R8) is the spec-side analog: structured edit on a single `<module>.spec.md`. Same forward iteration vs drift absorption modes (auto-detected from `drift_log.md ## Spec drift` pending rows). Engineering voice — schema sketches, code identifiers, file paths allowed (unlike PRD). One section at a time; no changelog markers; ~3000-word soft cap.
- `/super-manus:reverse-prd-spec` (v0.9.5 R9 — renamed from `/super-manus:reverse-prd`) runs three stages: Stage 1 declarative module discovery (compose / Makefile / source structure), Stage 2 a passive runtime probe via `scripts/probe-runtime.sh`, Stage 3 the `reverse-architect` agent (renamed from `reverse-prd-architect`) which cross-validates static reading against the probe's `runtime_facts` and writes PRD AND/OR spec depending on the user-selected scope (interactive `AskUserQuestion`: `both` / `prd` / `spec`; supports a 2nd positional arg for non-interactive). Spec-side refresh follows the section-aware policy: `## Data contracts` / `## Interface contracts` get full rewrites, `## Behavioral contracts` is seed-if-absent + append `(audit)` candidates, `## Design rationale` is never touched (100% human-curated). Three (audit) subtypes (`runtime-unverified` / `runtime-only` / `source-runtime-conflict`) flag specific kinds of static-vs-runtime disagreement. The Docker startup gate (offering `docker compose up -d` when compose services are stopped) goes through `AskUserQuestion`; the probe script itself never invokes mutating commands.
- **Per-agent model + effort routing** — every agent declares `model:` and `effort:` in its frontmatter. Thinkers (`impl-architect`, `impl-reviewer`, `reverse-architect`) are pinned `model: opus` + `effort: max` as the quality floor; writers (`impl-test-writer`, `impl-code-writer`, `sync-planner`) use `model: inherit` + `effort: high` so the main session's model flows through. Users override `model:` per-agent via `.super-manus/agents.yml` (read by `sm_agent_model` in `hooks/lib.sh`); each spawning command (impl / impl-all / reverse-prd-spec / sync) passes the result as the Agent tool's `model:` parameter. `effort:` is overridden via `CLAUDE_CODE_EFFORT_LEVEL` env var (Claude Code's highest-priority effort source — overrides frontmatter).
- Skills `tdd-in-phases` / `verification-before-phase-close` / `systematic-debugging-in-phase` are invoked by `/super-manus:impl` during phase execution. `using-sm` is the umbrella skill invoked by every `/super-manus:*` command.

## PR governance

- Small commits, one logical change per commit.
- Commit messages follow the conventional style already in `git log` (`feat:`, `fix:`, `docs:`, `chore:`, `test:`).
- Never `git push --force` to `main`. If history needs rewriting, do it on a branch and open a PR.
- Run `bash tests/run-all.sh` before declaring any task done. A green run is the bar — not "looks right to me".
- Never commit `.DS_Store`, editor swap files, or anything outside the four-file commit you intended.

## Where to look

- `docs/design-v0.9.8.md` — current engineering-wiki-layer design (v0.9.8). Read before changing the `wiki/` directory layout, `wiki_index.md` / `wiki_log.md` schemas, the `sm_load_wiki` helper, the v0.9.8 R17 simplification of cross-phase memory (`sm_load_update_reflections` replaces `sm_collect_reflections`; same-update only, no filter, no K-cap), the four wiki injection points in `/super-manus:impl`, the reviewer `wiki-candidates:` verdict field, the orchestrator promote gate, the wiki-vs-spec decision tree, or `/super-manus:wiki-lint` (standalone + drift-gate Pass 4).
- `docs/design-v0.9.7.md` — multi-author baseline design (v0.9.7). Read before changing `.gitattributes` merge rules, the `templates/codeowners.example` template, or the `drift_log.md` 5-column schema with Author cell.
- `docs/design-v0.9.6.md` — test-writer Reflexion + PRD↔spec topic-overlap radar design (v0.9.6). Read before changing the test-writer spawn inputs, the `## Honor prior_reflections` test-writer procedure, the post-edit topic-overlap check in `prd-update` / `spec-update`, or the `acknowledged-soft:` Resolution discipline.
- `docs/design-v0.9.5.md` — spec-layer + drift-log-rename design (v0.9.5). Read before changing the per-module `<module>.spec.md` shape, the `/super-manus:spec-update` command, the `reverse-prd-spec` rename + scope question, the section-aware refresh policy, or the `drift_log.md` two-section structure.
- `docs/design-v0.9.0.md` — reviewer-upgrade design (v0.9.0). Read before changing edge-case enumeration discipline, the pre-close test-run requirement, or the reviewer's grep/Read budget.
- `docs/design-v0.8.md` — v0.8 design. Read before changing the runtime probe, Cross-validation protocol, model/effort routing, or `agents.yml` override mechanism.
- `docs/design-v0.*.md` (other) — earlier design rationale. Consult when you need to understand *why* a current invariant exists; not required reading for normal contributions.
- `docs/plans/` — per-task implementation plans.
