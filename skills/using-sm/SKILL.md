---
name: using-sm
description: How to read and write super-manus state files (v0.2 two-axis model — module × milestone — with prd/ folder, impl/<module>/<update>/ folders, roadmap.md, prd_drift.md). Triggered by /super-manus:* slash commands and SessionStart/Stop/PostToolUse hook reminders in super-manus-enabled projects.
user-invocable: false
---

# using-sm (v0.2)

The super-manus plugin keeps a per-feature folder on disk so state survives `/clear`, `/compact`, and full session boundaries. This skill teaches you the read/write protocol for the **v0.2** layout. Follow it whenever a `/super-manus:*` command runs or a hook reminder references "the using-sm skill conventions".

The v0.2 model has **two axes**: `module` (space) and `milestone update` (time). PRD is per-module target state; implementation work is per-module per-milestone time series. v0.1 features (a flat folder with single `prd.md` + four-file set at the root) keep working through hook fallbacks; this skill describes v0.2 first, with a v0.1 compatibility note at the end.

User-facing commands (all in the `/super-manus:` namespace):

- `/super-manus:start <name>` — create a new feature folder + activate it
- `/super-manus:brainstorm` — 5-question Q&A; writes `prd/_index.md` + per-module `prd/<module>.md` stubs + auto-seeds the first MVP update for the first listed module
- `/super-manus:reverse-prd` — one-shot: scan an existing project, infer module split, generate `prd/_index.md` + per-module PRD stubs (user audits)
- `/super-manus:sync <module>` — after a PRD edit, scaffold a new milestone-update folder for the chosen module, drift-checked against `prd/<module>.md`
- `/super-manus:prd-update <module>` — surgical 5-option edit on a single per-module PRD (no changelog markers, ≤2000 words, single-section)
- `/super-manus:impl [target]` — resume / advance work in the active update; auto-selects next pending phase, seeds `tasks/p<n>_impl.md`, drift-checks, then executes
- `/super-manus:drive` — global next-action switch: read full feature state, decide one of brainstorm / sync / prd-update / impl, announce decision + reason, execute inline

The recommended flow for a non-trivial v0.2 feature: `start` → `brainstorm` → audit `prd/<module>.md` files → `impl` (or `drive`) → commit → … → on PRD change: `prd-update` or hand-edit `prd/<module>.md` → `sync` → `impl`.

## 1. Where state lives

```
<project-root>/
├── .super-manus/
│   └── active                                   # text file: current feature folder name
└── docs/super-manus/
    └── <YYYY-MM-DD>-<feature-name>/
        ├── prd/
        │   ├── _index.md                        # feature-level: Problem / Demo / Must / Not / Modules / Data flow (≤700 words)
        │   └── <module>.md                      # per-module: Purpose / Surface / Data flow / Constraints / Out of scope / Open questions (≤2000 words)
        ├── impl/
        │   └── <module>/
        │       └── <YYYY-MM-DD>-<update-name>/
        │           ├── task_plan.md             # phase index for THIS update (Goal + Phases table)
        │           ├── findings.md              # decisions / errors / data points for THIS update
        │           ├── progress.md              # commits + session log for THIS update (hook-managed)
        │           └── tasks/
        │               └── p<n>_impl.md         # per-phase technical plan, lazy-created by /super-manus:impl
        ├── roadmap.md                           # module status table (auto-managed)
        └── prd_drift.md                         # PRD ↔ implementation conflict log (append-only)
```

**Two axes**: `prd/<module>.md` is the module's TARGET STATE (does not move with implementation). `impl/<module>/<update>/` is the module's TIME SERIES (each milestone update is a folder; old updates are immutable historical record). The internal four-file set inside an update folder uses the same schema as v0.1's feature-root files — `task_plan.md ## Goal` is a one-sentence summary + pointer to the per-module PRD; everything else follows v0.1 conventions inside that update.

`.super-manus/active` contains just the feature folder basename. Switch features with `/super-manus:switch`; create new ones with `/super-manus:start`. Always resolve the active feature folder by reading `.super-manus/active` first — never hard-code a path.

**Active update resolution.** There is NO second active-state file. Hooks and commands resolve "the current active update" by calling `sm_active_update <feature>` (sourced from `${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh`), which scans `impl/<module>/` across all modules and returns `<module>/<update-folder>` of the most recently modified subfolder. If the result is empty, the hook no-ops; the agent suggests `/super-manus:brainstorm` or `/super-manus:sync <module>`.

## 2. What goes in which file

**`prd/_index.md`** — feature-level overview + module manifest (`## Problem` / `## Demo` / `## Must` / `## Not doing` / `## Modules` / `## Data flow overview`).
- Total length ≤ 700 words. The `## Modules` table (`| Module | File | Purpose |`) is the source of truth for which modules exist.
- **Not for**: per-module schema, endpoints, UX details. Those live in `prd/<module>.md`.

**`prd/<module>.md`** — per-module target state (`## Purpose` / `## Surface` / `## Data flow` / `## Constraints` / `## Out of scope` / `## Open questions`).
- Total length ≤ 2000 words. `## Surface` is the key new section vs v0.1: it allows schema sketches (table + field lists), endpoint paths, screen flows — at the level of "this is what the module IS", not "how this phase MIGRATES to it".
- **No changelog markers**: no `~~strikethrough~~`, no `(was: ...)`, no dated revision marks, no "moved from Surface" breadcrumbs. PRD is a current-state snapshot; history lives in `findings.md` and `git log`.
- **Not for**: code snippets, file paths, line numbers, function names — those are tasks/p<n>_impl.md territory. Schema sketches at the level of "table X has fields a, b, c" are fine; raw migration code is not.

**`impl/<module>/<YYYY-MM-DD>-<update-name>/task_plan.md`** — phase index for ONE milestone update.
- `## Goal`: ONE SENTENCE distilling this update's intent, ending with a pointer to `../../../prd/<module>.md`.
- `## Phases`: markdown table with columns `# | Name | Status | Notes`.
- Status values: `pending` / `in_progress` / `blocked` / `closed` (lowercase, exact). Used by hooks and `scripts/refresh-outstanding.sh`.
- **Not for**: code, multi-line implementation sketches, OR product-spec details. Product → `prd/<module>.md`. Implementation → `tasks/p<n>_impl.md`.

**`impl/<module>/<YYYY-MM-DD>-<update-name>/findings.md`** — working memory for THIS update. Tight entries.
- `## Decisions`: dated entries, **3 short lines max each**: `Chose: <one sentence>` / `Why: <one sentence>` / `Ruled out: <one sentence, optional>`. **No** code blocks, file paths, line numbers, function names, test command names. The artifact lives in `tasks/p<n>_impl.md` and commit messages — `findings.md` records the *judgment*, not the *artifact*. PRD revisions get a paired entry here when `/super-manus:prd-update <module>` runs.
- `## Errors`: table `When | What failed | Resolution`. Each cell ≤ one short sentence.
- `## Data points / research`: bullet form. Smoke numbers, eval scores, links.

**`impl/<module>/<YYYY-MM-DD>-<update-name>/progress.md`** — auto-managed; treat as read-only by default.
- `## Completed commits`: post-commit hook appends one line per `git commit` (Bash-tool calls only).
- `## Session log`: Stop hook surfaces a checkpoint every N turns OR when there are commits since the latest entry; agent judges whether to write.
- `## Outstanding`: regenerated from THIS update's `task_plan.md` by `scripts/refresh-outstanding.sh "<update-folder>"` — never edit by hand.

**`impl/<module>/<YYYY-MM-DD>-<update-name>/tasks/p<n>_impl.md`** — per-phase technical plan (lazy).
- Created by `/super-manus:impl` when the next pending phase needs a plan. Trivial phases don't need one.
- Sections: `## Objective` (what "done" means) / `## Approach` (chosen technical route — DB schema, API endpoints, code snippets, file diffs all live here) / `## Files touched` / `## Verification`.
- Lifecycle: fill `## Objective` first, evolve `## Approach` in place, leave the file as historical record when the phase closes.

**`roadmap.md`** — module status table. `| Module | Status | Note |`. Status values: `not-started` / `iterating` / `stable` / `blocked`.
- Auto-managed by `/super-manus:start` (empty), `/super-manus:brainstorm` (rows added at `not-started`), `/super-manus:sync` (flips `not-started` → `iterating`), `/super-manus:impl` (flips `iterating` → `stable` once an update's phases are all `closed` AND no pending drift remains).
- The Note column is **user-owned** — agent must not overwrite a user-written note.

**`prd_drift.md`** — append-only PRD ↔ implementation conflict log. `| When | Module | Conflict | Resolution |`.
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

**Drift detection responsibility (new in v0.2).** When running `/super-manus:impl`, `/super-manus:sync`, or `/super-manus:drive`, you must compare the user's stated intent / commit messages against `prd/<module>.md ## Surface` / `## Constraints` / `## Out of scope`. If you see a capability that PRD doesn't declare, append one row to `prd_drift.md` with `Resolution = pending` and stop the user with two paths: (1) revert implementation, or (2) `/super-manus:prd-update <module>`. Do **not** silently update PRD. The mechanics of *how* to compare PRD claims against actual code are defined in §4 (Drift check protocol).

## 4. Drift check protocol

When `/super-manus:reverse-prd`, `/super-manus:sync`, `/super-manus:impl`, or `/super-manus:prd-update` need to compare PRD claims against the actual codebase, follow this protocol. It is the single source of truth for PRD↔code cross-checking — commands reference it, they don't reinvent it.

### Tool roles

LSP gives structural truth from indexed code. grep / Read gives textual signals from filesystem and non-code artifacts. Use them in concert — they answer different questions and reinforce each other on the overlapping ones.

| Inference target | Primary | Secondary | How they combine |
|---|---|---|---|
| Module boundaries | grep (top-level dirs, manifest workspaces) | LSP workspace symbols clustered by file path | Both agree → firm module; disagree → `(audit)` |
| `## Surface` signatures (real exports, endpoints) | LSP document symbols on the relevant file | grep to locate the file (route, migration, CLI entry) | grep finds the file, LSP names the symbol — only LSP-confirmed names enter PRD |
| Cross-module data flow | LSP find-references on each export | grep for imports, env vars, config-driven dispatch | LSP gives the call graph; grep covers what LSP can't index |
| Constraints (timeout, license, PII, TODO) | grep | — | text-only signal; LSP irrelevant |
| Purpose / Demo / intent | Read (README, manifest description) | — | product intent, not code structure; LSP irrelevant |

### Concrete LSP operations

- **workspace symbols** — initial pass: every exported symbol with location; cluster by file path to validate folder-based module guesses.
- **document symbols** — per-module pass: enumerate the public surface of one file before writing its `## Surface`.
- **find-references** — per-export pass: who calls this module's exports → real cross-module wiring for `## Data flow`.

### Double-source rule

A claim entering PRD `## Surface` / `## Data flow` / `## Constraints`, or a verdict entering `prd_drift.md`, must be confirmed by **both LSP and grep** when both apply. Single-source claims either get the `(audit)` marker in `prd/<module>.md` or land in `## Open questions`. Do not append a drift row from a single weak signal.

### Budget

- LSP: ≤10 workspace-symbol or find-references calls + 1 document-symbol per inferred module.
- grep / Read: ≤30 calls.

If you blow the budget without converging, stop and report. Exhaustive enumeration is out of scope.

### LSP unavailable fallback

If no language server is available (cold project, missing toolchain, polyglot repo with no active LSP for the module's language), continue with grep + Read alone. Every conclusion gets the `(audit)` marker since the double-source rule cannot be satisfied. The agent must surface "LSP unavailable — text-only inference" in the user-facing report so the audit list is taken seriously.

### Per-command application

- `/super-manus:reverse-prd` — full-codebase pass to bootstrap PRD; module boundaries and `## Surface` are LSP-led, Purpose / Demo are README-led.
- `/super-manus:sync <module>` — runs against the user's stated intent before scaffolding the update folder; LSP confirms whether the intent's surface already exists, grep confirms wiring.
- `/super-manus:impl` — runs against the next phase's intent and `tasks/p<n>_impl.md ## Objective` before drafting code; conflict appends `prd_drift.md`.
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
- Putting **DB schema, API endpoints, code, or any tech-design text** into `prd/<module>.md` deeper than the `## Surface` outline — schema *sketches* (table + fields) are fine; migration code or full request/response DTO definitions are not. Those live in `tasks/p<n>_impl.md ## Approach`.
- Pasting **TDD plan recaps, file lists, line numbers, function names, test commands, or block-A/B/C breakdowns** into `findings.md ## Decisions` — record the JUDGMENT (3 lines), not the IMPLEMENTATION ARTIFACT.
- **Putting changelog markers in any prd/ file** — no `~~strikethrough~~`, no "(was: ...)", no "v2 added X", no dated revision footers. PRD is current-state; history is in `git log` and `findings.md`.
- **Hand-editing `prd_drift.md`** — only `sync` / `impl` / `drive` append; only `prd-update` resolves. Never reorder rows or rewrite history here.
- **Overwriting the user's Note column in `roadmap.md`** — flip Status, leave Note alone unless the user explicitly asked.
- **Silently updating PRD** when implementation diverges — always log a drift row and let the user decide.
- Reordering or renaming schema headings — hooks parse by exact heading name (`## Phases`, `## Outstanding`, `## Completed commits`, `## Session log`, `## Modules`, etc.) and will silently produce wrong output if you rename them.
- Creating ad-hoc files (`notes.md`, `decisions.md`, `todo.md`, `tests.md`) inside the feature folder — keep state in the canonical files.
- Hand-editing `## Outstanding` in any `progress.md` — `scripts/refresh-outstanding.sh` overwrites it on the next refresh.

## 8. v0.1 compatibility

If the active feature folder has `prd.md` as a *file* (not `prd/` as a directory), it's v0.1. The hooks fall back to v0.1 paths automatically (`<feature>/progress.md`, `<feature>/task_plan.md`). The legacy commands `/super-manus:phase <n>`, `/super-manus:catchup`, and `/super-manus:log` keep working on v0.1 features. There is no automatic migration — v0.2 only applies to features started with the v0.2 `/super-manus:start`.

---

*The 2-action rule and 3-strike error protocol are borrowed from [planning-with-files](https://github.com/OthmanAdi/planning-with-files).*
