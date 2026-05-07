---
name: using-sm
description: How to read and write super-manus state files. Triggered by /super-manus:* slash commands and SessionStart/Stop/PostToolUse hook reminders in super-manus-enabled projects.
user-invocable: false
---

# using-sm

super-manus keeps a project-global folder on disk so state survives `/clear`, `/compact`, and full session boundaries. This skill is the read/write protocol; follow it whenever a `/super-manus:*` command runs or a hook reminder references "the using-sm skill conventions". Two axes: `module` (space) and `milestone update` (time). PRD is per-module target state (project-global, one snapshot per project); implementation work is per-module per-milestone time series.

User commands live under `commands/`; see each file's frontmatter for description. Recommended flow: `start` → `brainstorm` → audit `prd/<module>.md` → `sync <module>` → `impl` (or `drive`) → commit → on PRD change: `prd-update` (forward or drift mode, auto-detected) or hand-edit + `sync` → `impl`.

## 1. Where state lives

```
<project-root>/
└── docs/super-manus/
    ├── prd/                                     ← project-global, ONE source of truth
    │   ├── _index.md                            ← 8 PM-flavored H2 sections (Problem / Audience / Success metrics / Demo / Must / Not doing / Modules / Data flow overview); ≤700 words
    │   └── <module>.md                          ← 9 PM-flavored H2 sections (Why this exists / Users / Success / What users get / How it connects / Quality bar / Risks / Out of scope / Open questions); ≤2000 words
    ├── e2e/                                     ← v0.5 NEW: permanent regression suite, mirrors prd/
    │   ├── _system/                             ← cross-module scenarios from prd/_index.md ## Demo
    │   │   └── test_<scenario>.<ext>            ← auto-discovered by default test runner; runs in CI
    │   └── <module>/                            ← per-module capabilities from prd/<module>.md ## What users get
    │       └── test_<capability>.<ext>          ← auto-discovered by default test runner; runs in CI
    ├── roadmap.md                               ← project-global, module status table (auto-managed)
    ├── prd_drift.md                             ← project-global, append-only PRD ↔ implementation drift log
    └── impl/                                    ← time series of milestones, per module
        └── <module>/
            └── <YYYY-MM-DD>-<update-name>/      ← only place timestamps appear
                ├── task_plan.md                 ← phase index for THIS update (Goal + Phases table)
                ├── findings.md                  ← decisions / errors / data points for THIS update
                ├── progress.md                  ← commits + session log for THIS update (hook-managed)
                ├── tasks/
                │   └── p<n>_impl.md             ← per-phase technical plan, lazy-created by /super-manus:impl
                └── tests/                       ← v0.5 NEW: phase tests for THIS update, NOT auto-discovered
                    └── phase_p<n>_<verb>_<noun>.<ext>
```

**Two axes**: `prd/<module>.md` is the module's TARGET STATE (does not move with implementation). `impl/<module>/<update>/` is the module's TIME SERIES (each milestone update is a folder; old updates are immutable historical record).

**Two test tiers** (v0.5):

- `docs/super-manus/e2e/<module>/test_<capability>.<ext>` and `docs/super-manus/e2e/_system/test_<scenario>.<ext>` — **permanent regression**, mirrors PRD's module/_index structure, auto-discovered by default test runner globs (pytest `test_*.py`, jest `*.test.ts`), runs in CI on every commit. Lifetime: as long as the capability lives in PRD.
- `docs/super-manus/impl/<m>/<u>/tests/phase_p<n>_<verb>_<noun>.<ext>` — **phase tests**, milestone-scoped, NOT auto-discovered (`phase_*` prefix in Python or `*.phase.ts` suffix in Node/TS is chosen specifically to fall outside default runner globs), invoked by `/super-manus:impl` via explicit path. Lifetime: as long as the milestone update folder exists.

The naming distinction is load-bearing — orchestrator and CI configs depend on it. Phase tests go through explicit-path invocation by the orchestrator; e2e tests are picked up by the project's pre-existing test runner globs.

**No active-state file.** There is NO `.super-manus/active` and no second active-state file. Hooks and commands resolve "the current active update" by calling `sm_active_update` (sourced from `${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh`, **no arguments** in v0.4), which scans `docs/super-manus/impl/<module>/*/` across all modules and returns `<module>/<update-folder>` of the most recently modified subfolder. If the result is empty, the hook no-ops; the agent suggests `/super-manus:brainstorm` or `/super-manus:sync <module>`.

**super-manus enabled?** A project is super-manus-enabled iff `docs/super-manus/prd/` exists as a directory. Hooks check this before doing anything.

## 2. What goes in which file

**`docs/super-manus/prd/_index.md`** — project-level overview + module manifest (`## Problem` / `## Audience` / `## Success metrics` / `## Demo` / `## Must` / `## Not doing` / `## Modules` / `## Data flow overview`).
- Total length ≤ 700 words. The `## Modules` table (`| Module | File | Purpose |`) is the source of truth for which modules exist.
- `## Audience` names primary + secondary users with their trigger moments. `## Success metrics` is the top 3 user/business KPIs (target + measurement method) — NOT infra metrics like "uptime > 99%".
- **Not for**: per-module schema, endpoints, UX details, per-module risks. Those live in `prd/<module>.md`.

**`docs/super-manus/prd/<module>.md`** — per-module target state (`## Why this exists` / `## Users` / `## Success` / `## What users get` / `## How it connects` / `## Quality bar` / `## Risks` / `## Out of scope` / `## Open questions`).
- Total length ≤ 2000 words. `## What users get` lists 3–5 capabilities in PM voice with technical evidence appended (`Backed by: <schema | endpoint | screen | CLI>`) — at the level of "this is what the module IS", not "how this phase MIGRATES to it". Schema sketches (table + field lists), endpoint paths, screen flows go here.
- `## Why this exists` is 2 sentences of PM framing (user pain + business value), NOT "this module wraps X". `## Users` names the persona + trigger moment (internal modules name their upstream callers). `## Success` is 3–5 measurable user-facing outcomes — NOT "tests pass" / "uptime > 99%". `## How it connects` opens with an Exposes/Consumes semantic preamble (PM-voice capability names crossing the module boundary), then carries upstream/downstream/third-party in plain language plus a precise edge list. `## Quality bar` is user-visible NFRs (perf, scale, compliance) only — internal infra ("uses Postgres") belongs under `## How it connects`. `## Risks` covers Product / Technical / Org+dependency in 2–4 bullets total.
- **No changelog markers**: no `~~strikethrough~~`, no `(was: ...)`, no dated revision marks, no "moved from <section>" breadcrumbs. PRD is a current-state snapshot; history lives in `findings.md` and `git log`.
- **Not for**: code snippets, file paths, line numbers, function names — those are tasks/p<n>_impl.md territory. Schema sketches at the level of "table X has fields a, b, c" are fine; raw migration code is not.

**`docs/super-manus/impl/<module>/<YYYY-MM-DD>-<update-name>/task_plan.md`** — phase index for ONE milestone update.
- `## Goal`: ONE SENTENCE distilling this update's intent, ending with a pointer to `../../../prd/<module>.md`.
- `## Phases`: markdown table with columns `# | Name | Status | Notes`.
- Status values: `pending` / `in_progress` / `blocked` / `closed` (lowercase, exact). Used by hooks and `scripts/refresh-outstanding.sh`.
- **Not for**: code, multi-line implementation sketches, OR product-spec details. Product → `prd/<module>.md`. Implementation → `tasks/p<n>_impl.md`.

**`docs/super-manus/impl/<module>/<YYYY-MM-DD>-<update-name>/findings.md`** — working memory for THIS update. Tight entries.
- `## Decisions`: dated entries, **3 short lines max each**: `Chose: <one sentence>` / `Why: <one sentence>` / `Ruled out: <one sentence, optional>`. **No** code blocks, file paths, line numbers, function names, test command names. The artifact lives in `tasks/p<n>_impl.md` and commit messages — `findings.md` records the *judgment*, not the *artifact*. PRD revisions get a paired entry here when `/super-manus:prd-update <module>` runs.
- `## Errors`: table `When | What failed | Resolution`. Each cell ≤ one short sentence.
- `## Data points / research`: bullet form. Smoke numbers, eval scores, links.

**`docs/super-manus/impl/<module>/<YYYY-MM-DD>-<update-name>/progress.md`** — auto-managed; treat as read-only by default.
- `## Completed commits`: post-commit hook appends one line per `git commit` (Bash-tool calls only).
- `## Session log`: Stop hook surfaces a checkpoint every N turns OR when there are commits since the latest entry; agent judges whether to write.
- `## Outstanding`: regenerated from THIS update's `task_plan.md` by `scripts/refresh-outstanding.sh "<update-folder>"` — never edit by hand.

**`docs/super-manus/impl/<module>/<YYYY-MM-DD>-<update-name>/tasks/p<n>_impl.md`** — per-phase technical plan (lazy).
- Created by `/super-manus:impl` when the next pending phase needs a plan. Trivial phases don't need one.
- Sections: `## Objective` (what "done" means) / `## Approach` (chosen technical route — DB schema, API endpoints, code snippets, file diffs all live here) / `## Files touched` / `## Verification`.
- Lifecycle: fill `## Objective` first, evolve `## Approach` in place, leave the file as historical record when the phase closes.

**`docs/super-manus/roadmap.md`** — module status table. `| Module | Status | Note |`. Status values: `not-started` / `iterating` / `stable` / `blocked`.
- Auto-managed by `/super-manus:start` (empty), `/super-manus:brainstorm` (rows added at `not-started`), `/super-manus:sync` (flips `not-started` → `iterating`), `/super-manus:impl` (flips `iterating` → `stable` once an update's phases are all `closed` AND no pending drift remains).
- The Note column is **user-owned** — agent must not overwrite a user-written note.

**`docs/super-manus/prd_drift.md`** — append-only PRD ↔ implementation conflict log. `| When | Module | Conflict | Resolution |`.
- Rows appended by `/super-manus:sync`, `/super-manus:impl`, and `/super-manus:drive` when they detect a conflict.
- Resolution column is updated by `/super-manus:prd-update <module>` when the user takes the "update PRD" path; left as `pending` otherwise.

## 3. When to update each file

| File | Trigger |
|---|---|
| `prd/_index.md` | First brainstorm; product framing or module split changes. Engineering changes never trigger this. |
| `prd/<module>.md` | First brainstorm seeds a stub; user audits/expands it; `/super-manus:prd-update <module>` makes a surgical edit (with paired `findings.md` decision entry). |
| `roadmap.md` | Auto-managed by `start` / `brainstorm` / `sync` / `impl`. Hand-edit only the Note column. |
| `prd_drift.md` | Append-only by `sync` / `impl` / `drive` on detected drift; Resolution updated by `prd-update`. |
| `task_plan.md` (per update) | A phase status changes (`closed` / `in_progress` / `blocked`); a new phase is added or split. `## Goal` only changes if the per-module PRD's framing changes. |
| `findings.md` (per update) | Any decision (with reasoning), any error, any research finding worth surviving the session. PRD revisions for this module also get a paired entry here. |
| `progress.md` (per update) | NEVER directly. Wait for a hook reminder. Post-commit hook tells you to append to `## Completed commits`; Stop hook checkpoint asks you to consider writing to `## Session log`. |
| `tasks/p<n>_impl.md` (per update) | A phase entered `in_progress`; the approach / DB schema / API design changes mid-phase; the verification step changes. |

**Drift detection responsibility.** When running `/super-manus:impl`, `/super-manus:sync`, or `/super-manus:drive`, you must compare the user's stated intent / commit messages against `prd/<module>.md ## What users get` / `## Quality bar` / `## Out of scope`. If you see a capability that PRD doesn't declare (or one that violates the Quality bar), append one row to `prd_drift.md` with `Resolution = pending` and stop the user with two paths: (1) revert implementation, or (2) `/super-manus:prd-update <module>`. Do **not** silently update PRD. The mechanics of *how* to compare PRD claims against actual code are defined in §4 (Drift check protocol).

## 4. Drift check protocol

When `/super-manus:reverse-prd`, `/super-manus:sync`, `/super-manus:impl`, or `/super-manus:prd-update` need to compare PRD claims against the actual codebase, follow this protocol. It is the single source of truth for PRD↔code cross-checking — commands reference it, they don't reinvent it.

### Tool roles

LSP gives structural truth from indexed code. grep / Read gives textual signals from filesystem and non-code artifacts. Use them in concert — they answer different questions and reinforce each other on the overlapping ones.

| Inference target | Primary | Secondary | How they combine |
|---|---|---|---|
| Module boundaries | grep (top-level dirs, manifest workspaces) | LSP workspace symbols clustered by file path | Both agree → firm module; disagree → `(audit)` |
| `## What users get` signatures (real exports, endpoints) | LSP document symbols on the relevant file | grep to locate the file (route, migration, CLI entry) | grep finds the file, LSP names the symbol — only LSP-confirmed names enter PRD |
| `## How it connects` cross-module wiring | LSP find-references on each export | grep for imports, env vars, config-driven dispatch | LSP gives the call graph; grep covers what LSP can't index |
| `## Quality bar` (timeout, rate limit, license, PII) and `## Risks` (TODO, HACK, known-broken) | grep | — | text-only signals; LSP irrelevant |
| `## Why this exists` / `## Users` / `## Success` / Demo / intent | Read (README, manifest description) | — | product intent, not code structure; LSP irrelevant |

### Concrete LSP operations

- **workspace symbols** — initial pass: every exported symbol with location; cluster by file path to validate folder-based module guesses.
- **document symbols** — per-module pass: enumerate the public surface of one file before writing its `## What users get`.
- **find-references** — per-export pass: who calls this module's exports → real cross-module wiring for `## How it connects`.

### Double-source rule

A claim entering PRD `## What users get` / `## How it connects` / `## Quality bar`, or a verdict entering `prd_drift.md`, must be confirmed by **both LSP and grep** when both apply. Single-source claims either get the `(audit)` marker in `prd/<module>.md` or land in `## Open questions`. Do not append a drift row from a single weak signal.

### Budget

- LSP: ≤10 workspace-symbol or find-references calls + 1 document-symbol per inferred module.
- grep / Read: ≤30 calls.

If you blow the budget without converging, stop and report. Exhaustive enumeration is out of scope.

### LSP unavailable fallback

If no language server is available (cold project, missing toolchain, polyglot repo with no active LSP for the module's language), continue with grep + Read alone. Every conclusion gets the `(audit)` marker since the double-source rule cannot be satisfied. The agent must surface "LSP unavailable — text-only inference" in the user-facing report so the audit list is taken seriously.

### Per-command application

- `/super-manus:reverse-prd` — full-codebase pass to bootstrap PRD; module boundaries and `## What users get` are LSP-led, `## Why this exists` / `## Users` / `## Success` / Demo are README-led. Writes to `docs/super-manus/prd/`.
- `/super-manus:sync <module>` — runs against the user's stated intent before scaffolding the update folder under `docs/super-manus/impl/<module>/`; LSP confirms whether the intent's capability already exists, grep confirms wiring.
- `/super-manus:impl` — runs against the next phase's intent and `tasks/p<n>_impl.md ## Objective` before drafting code; conflict appends `docs/super-manus/prd_drift.md`.
- `/super-manus:prd-update <module>` — for **Tighten** and **Demote**, verify the affected bullet against current code; **Split** runs on both halves; **Add** and **Exclude** don't need verification (they declare new intent or remove scope, not align).

## 5. The 2-action rule

After every 2 view/search/grep operations, write the key findings to the active update's `findings.md` before they fall out of context. Borrowed from [planning-with-files](https://github.com/OthmanAdi/planning-with-files): treat the file as RAM-extension. Externalize aggressively; the cost of an extra Edit is trivial compared to the cost of re-deriving a finding after `/compact`.

## 6. The 3-strike error protocol

When something fails (test, command, tool call):

- **Strike 1** — log to the active update's `findings.md ## Errors` table: `When | What failed | what you tried`.
- **Strike 2** (same error class, second time) — log AND mutate your approach. Try a different angle.
- **Strike 3** (same error class, third time) — log AND stop. Escalate to the user with a summary of what you tried, what you suspect, and what would unblock you.

The point is to surface tarpits early, not slog through them silently.

## 7. Anti-patterns

- Using TodoWrite for cross-session persistence — it resets on `/clear`. Use `task_plan.md ## Phases` (per active update).
- Writing to any `progress.md` without a hook reminder — you'll race the auto-managed sections.
- Putting errors in `task_plan.md` — they belong in `findings.md ## Errors` (per update).
- Pasting code, pseudo-code, file diffs, or multi-line sketches into `task_plan.md` — that's a phase index. Use `tasks/p<n>_impl.md`.
- Putting **product spec** (Problem statements, Demo scenarios, capability lists, success metrics) into `task_plan.md` — those belong in `prd/_index.md` or `prd/<module>.md`. `task_plan.md ## Goal` is one sentence + a pointer to the module PRD.
- Putting **DB schema, API endpoints, code, or any tech-design text** into `prd/<module>.md` deeper than the `## What users get` outline — schema *sketches* (table + fields) are fine; migration code or full request/response DTO definitions are not. Those live in `tasks/p<n>_impl.md ## Approach`.
- Pasting **TDD plan recaps, file lists, line numbers, function names, test commands, or block-A/B/C breakdowns** into `findings.md ## Decisions` — record the JUDGMENT (3 lines), not the IMPLEMENTATION ARTIFACT.
- **Putting changelog markers in any prd/ file** — no `~~strikethrough~~`, no "(was: ...)", no "v2 added X", no dated revision footers. PRD is current-state; history is in `git log` and `findings.md`.
- **Hand-editing `prd_drift.md`** — only `sync` / `impl` / `drive` append; only `prd-update` resolves. Never reorder rows or rewrite history here.
- **Overwriting the user's Note column in `roadmap.md`** — flip Status, leave Note alone unless the user explicitly asked.
- **Silently updating PRD** when implementation diverges — always log a drift row and let the user decide.
- **Inventing a per-feature wrapper folder** — v0.4 has none. PRD lives at `docs/super-manus/prd/`, not `docs/super-manus/<something>/prd/`. If you find yourself constructing a feature-prefixed path, you're working from outdated v0.2/v0.3 instructions.
- **Writing or reading `.super-manus/active`** — the file does not exist in v0.4. Always resolve via `sm_active_update` (no args).
- Reordering or renaming schema headings — hooks parse by exact heading name (`## Phases`, `## Outstanding`, `## Completed commits`, `## Session log`, `## Modules`, etc.) and will silently produce wrong output if you rename them.
- Creating ad-hoc files (`notes.md`, `decisions.md`, `todo.md`, `tests.md`) inside the super-manus folder — keep state in the canonical files.
- Hand-editing `## Outstanding` in any `progress.md` — `scripts/refresh-outstanding.sh` overwrites it on the next refresh.

## 8. Companion skills

`using-sm` is the state-protocol skill (what files exist, what goes in each, when to update). Three execution-discipline skills are invoked by `/super-manus:impl` and `/super-manus:impl-all` during phase execution:

| Skill | Invoked by | What it enforces |
| --- | --- | --- |
| `tdd-in-phases` | `impl-test-writer` step | test-writer is spawned BEFORE code-writer; phase tests at `docs/super-manus/impl/<m>/<u>/tests/phase_p<n>_<verb>_<noun>.<ext>`; e2e tests at `docs/super-manus/e2e/<module>/test_<capability>.<ext>` when this phase **completes** a `## What users get` capability; tests committed red; code-writer is forbidden from editing tests |
| `verification-before-phase-close` | orchestrator after `impl-code-writer` reports done | phase Status flips to `closed` only after every command in `tasks/p<n>_impl.md ## Verification` exits green; `## Verification` MUST contain (1) a phase-test path command and (2) one user-visible smoke command |
| `systematic-debugging-in-phase` | orchestrator when a `## Verification` command fails | follow the checklist (re-read Approach, re-read failing test, binary-search the diff, write a regression test, fix, re-run); same error class three times → escalate |

End-of-update drift gate has **Pass 3 — e2e coverage check**: every touched `## What users get` capability needs `e2e/<module>/test_<capability>.<ext>` to exist and pass. Missing or red → `pending` row in `prd_drift.md`, BLOCKS roadmap from flipping to `stable`.

## 9. Coding discipline (karpathy reference)

Single source of truth for the four `andrej-karpathy-skills:karpathy-guidelines` principles that super-manus agents follow when writing or modifying code:

1. **Surgical changes** — touch only what the task requires. Don't refactor adjacent code, don't "improve" unrelated formatting / comments, don't introduce abstractions for single-use code. Every changed line should trace directly to the task. Pre-existing dead code stays unless the user asks.
2. **Surface assumptions** — state what you're assuming explicitly. Present interpretations rather than picking silently. If unclear, stop and name the confusion. Don't guess invisibly.
3. **Verifiable success criteria** — every task ends with a green check: a test passes, a command exits 0, a user-observable behavior occurs. "It looks done" is not done. The phase plan's `## Verification` section is the literal expression of this inside super-manus.
4. **Avoid overcomplication** — minimum code that solves the problem. No flexibility / configurability / error handling that wasn't asked for. If you wrote 200 lines and 50 would do, rewrite.

Applies to every super-manus agent (impl-architect / impl-test-writer / impl-code-writer / reverse-prd-architect / sync-planner). Agents reference §9; do NOT inline-duplicate the four principles.

**Code-writing discipline only**, not code-reading tactics. For "should I LSP, grep, or Read?", there is NO super-manus rule — `impl-*` agents pick whatever fits inside the known module they're working in; `reverse-prd-architect` follows its own runtime-first protocol in [commands/reverse-prd.md](../commands/reverse-prd.md) Stage 1 (LSP NOT used for module discovery).
