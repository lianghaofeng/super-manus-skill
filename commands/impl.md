---
description: Resume / advance work in the active milestone-update; auto-selects next pending phase, spawns impl-architect to draft tasks/p<n>_impl.md, runs PRD drift check, then executes
---

This is the v0.4 successor to `/super-manus:phase`. Day-to-day execution entry. The user wants you to figure out where work is, draft the next phase's implementation plan if needed (delegated to the `impl-architect` subagent), check it against the module's PRD, and continue executing.

The slash command is a **thin orchestrator**. It does not write phase plan content itself; the `impl-architect` agent owns that. The orchestrator owns: target resolution, phase selection, drift checks, the BLOCKING end-of-update gate, and execution after approval.

## Resolve target

In v0.4 there is no `.super-manus/active` state file — the PRD is project-global at `docs/super-manus/prd/`, and the active update is resolved purely by mtime scan via `sm_active_update` (sourced from `${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh`).

If `docs/super-manus/prd/` is not a directory, tell the user this project is not super-manus-enabled — they should run `/super-manus:start` first; then stop. If `docs/super-manus/impl/` is empty (no module subfolders), suggest `/super-manus:brainstorm` or `/super-manus:sync <module>`; then stop.

The user may pass a `target` argument:

- **Omitted** — use `sm_active_update "docs/super-manus"` to resolve the most recently modified update folder across all modules. The helper echoes `<module>/<update-name>`. If empty, suggest `/super-manus:sync <module>`.
- **Looks like a module name** (matches a `docs/super-manus/prd/<x>.md` file or a `docs/super-manus/roadmap.md` Module column entry) — find the most recently modified update folder under `docs/super-manus/impl/<target>/`. If none, suggest `/super-manus:sync <target>`.
- **Looks like an update folder name** (`<YYYY-MM-DD>-<name>`) — search `docs/super-manus/impl/*/<target>/`; if exactly one match, use it. If none, error and list candidates.

Heuristic: if `target` starts with a 4-digit year then dash, treat it as an update name. Otherwise treat as module.

Once resolved, set `UPDATE_DIR=docs/super-manus/impl/<module>/<update-name>` and `MODULE=<module>` for the rest of this run. Note: paths are project-global; there is no `<feature>/` prefix in v0.4.

## Pick next phase

Read `$UPDATE_DIR/task_plan.md ## Phases` table. Find:

1. The first row whose Status is `in_progress` — that's where to continue. If absent, fall through.
2. The first row whose Status is `pending` — that's where to begin. Flip its Status to `in_progress` (one-line edit in task_plan.md).
3. If no `in_progress` and no `pending` phases remain, all phases are `closed` or `blocked`. Skip ahead to the **End-of-update drift gate** below — the gate decides whether the update is done. Do NOT short-circuit "all closed → done" without running the gate.

Let `n` and `<phase name>` be the chosen row's `#` and `Name`.

## Drift check (BEFORE spending agent budget)

Run the **Drift check protocol** in [skills/using-sm/SKILL.md §4](../skills/using-sm/SKILL.md). The protocol is the shared LSP + grep cross-check used by `sync` / `impl` / `prd-update` / `reverse-prd` — this command consumes it before the impl-architect is spawned.

The order is deliberate: drift check first (cheap), then `impl-architect` (agent budget). If drift would block the work, we don't spend agent budget on a plan that will be discarded.

Concretely:

1. Read the per-module PRD `docs/super-manus/prd/<module>.md` (i.e. `docs/super-manus/prd/$MODULE.md`) — focus on `## What users get`, `## Quality bar`, `## Out of scope`.
2. Read the existing `$UPDATE_DIR/tasks/p<n>_impl.md ## Objective` if it already exists with substantive content; otherwise use the user's stated intent for this turn (and the phase Name from task_plan.md) as the proxy intent.
3. Apply the protocol against the phase intent. **LSP** (`document symbols` on the files the phase will touch; `find-references` on any cross-module export it touches) tells you whether the intent's capability already exists or is brand-new; **grep** covers wiring and quality-bar text LSP can't index. The double-source rule applies — only call drift when both LSP and grep (where applicable) agree the phase diverges from PRD.
4. If LSP is unavailable for this module's language, fall back per the protocol (grep + Read only) and surface "LSP unavailable — drift verdict is text-only inference" in the appended row's Conflict cell.

Decide: does the phase intent introduce a capability not declared in `## What users get`, or does it conflict with `## Out of scope` or violate `## Quality bar`?

- **No conflict** → continue to "Spawn impl-architect".
- **Conflict** → append one row to `docs/super-manus/prd_drift.md` (project-global drift log, not per-feature):
  ```
  | <YYYY-MM-DD> | <module> | <one-line conflict description> | pending |
  ```
  Then tell the user: "Drift detected in phase <n> (`<phase-name>`) of `<module>`. Two paths:
  1. Revert the phase intent to match PRD `## What users get` / `## Quality bar` / `## Out of scope`.
  2. Run `/super-manus:prd-update $MODULE` first, then re-run `/super-manus:impl`."
  Stop. Do NOT proceed to spawning the agent or writing code. The user must decide.

## Spawn impl-architect

If no drift, the orchestrator delegates per-phase impl-plan drafting to the `impl-architect` subagent (Agent tool, `subagent_type="impl-architect"`). The agent owns the persona ("senior implementation planner"), the four-section template population (`## Objective`, `## Approach`, `## Files touched`, `## Verification`), and the source-priority hierarchy. Do NOT inline that persona here — see [agents/impl-architect.md](../agents/impl-architect.md).

Why a subagent: phase-plan drafting needs LSP + grep budget on the module's entry files plus a focused PM/engineering voice. Embedding it in the main thread bloats orchestrator context and fragments the persona.

### Probe LSP availability once

Before spawning, attempt one workspace-symbol call against the module to set `lsp_available=true|false`. Pass the boolean to the agent so it can apply the protocol's fallback path correctly.

### Inputs to pass in the spawning prompt

Compute these from the resolved target and pass them in the Agent tool's `prompt` field:

- `project_root` — current working directory absolute path
- `module` — `$MODULE`
- `update_dir` — `$UPDATE_DIR` absolute path
- `phase_number` — `n`
- `phase_name` — the row's Name cell, verbatim
- `module_prd_path` — `docs/super-manus/prd/<module>.md` absolute path
- `task_plan_path` — `$UPDATE_DIR/task_plan.md`
- `findings_path` — `$UPDATE_DIR/findings.md`
- `progress_path` — `$UPDATE_DIR/progress.md`
- `lsp_available` — `true` or `false`

### Spawning prompt skeleton

> Inputs from /super-manus:impl orchestrator:
>
> - project_root: `<absolute path>`
> - module: `<module>`
> - update_dir: `<absolute path>`
> - phase_number: `<n>`
> - phase_name: `<name>`
> - module_prd_path: `<absolute path>`
> - task_plan_path: `<absolute path>`
> - findings_path: `<absolute path>`
> - progress_path: `<absolute path>`
> - lsp_available: `<true|false>`
>
> Draft (or resume) `${update_dir}/tasks/p<n>_impl.md` per your agent definition. Return the summary line when done.

The agent writes `$UPDATE_DIR/tasks/p<n>_impl.md` directly via the Write/Edit tools, seeding from `${CLAUDE_PLUGIN_ROOT}/templates/phase_plan.md` if the file does not yet exist (the template carries the four stable headings `## Objective` / `## Approach` / `## Files touched` / `## Verification`). It does NOT print the file to chat and it does NOT write code. If the file already has substantive content, it is idempotent — it returns "phase plan already drafted; resume from existing" and the orchestrator continues.

### After the subagent returns

The orchestrator MUST:

1. Verify `$UPDATE_DIR/tasks/p<n>_impl.md` exists and has non-empty `## Objective`, `## Approach`, `## Files touched`, `## Verification` sections.
2. If any of the four headings is missing or empty, surface a one-line warning to the user ("impl-architect produced an incomplete plan; please review tasks/p<n>_impl.md before continuing") — do NOT silently fix.
3. Surface the agent's summary line verbatim to the user.

Engineering detail (DB schema, API endpoints, code snippets, file diffs) lives in this phase plan — NOT in the per-module PRD. The PRD answered "this module IS what"; this phase plan answers "this phase DOES what".

## Execute

After the impl plan is drafted (and approved by the user — the orchestrator pauses here for confirmation on the first non-trivial phase), the **main agent (orchestrator) writes the code per the phase plan** in its own thread. Standard execution flow: TDD where applicable, edits, commits. The post-commit hook will append commit lines to `$UPDATE_DIR/progress.md`. Do **not** hand-edit `progress.md` — it's hook-managed.

When a phase is verified done, flip its row in `$UPDATE_DIR/task_plan.md` to `closed`. After flipping, run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/refresh-outstanding.sh" "$UPDATE_DIR"
```

to regenerate `progress.md ## Outstanding`.

## End-of-update drift gate (BLOCKING)

When all phases in `$UPDATE_DIR/task_plan.md` are `closed`, the update is **NOT done** until `docs/super-manus/prd_drift.md` (the project-global drift log) has zero rows where `Module = $MODULE` AND `Resolution = pending`. The gate runs in two passes.

### Pass 1 — Refresh drift from this update's commits

Read `docs/super-manus/prd/$MODULE.md` (`## What users get`, `## Quality bar`, `## Out of scope`) and `$UPDATE_DIR/progress.md ## Completed commits`. Apply the **Drift check protocol** at the commit level:

- **"PRD declared but not implemented"** — for each bullet in `## What users get` / `## Quality bar` that no commit visibly satisfies, append to `docs/super-manus/prd_drift.md`:
  ```
  | <YYYY-MM-DD> | $MODULE | <bullet text> declared but not in commits | pending |
  ```
- **"Implemented but not in PRD"** — for each capability visible in commits that is not declared in PRD, append:
  ```
  | <YYYY-MM-DD> | $MODULE | <capability> shipped but not in prd/$MODULE.md | pending |
  ```

The double-source rule still applies: only append a drift row when both LSP and grep (where applicable) agree the gap is real.

### Pass 2 — Block until pending = 0

Read `docs/super-manus/prd_drift.md`. Count rows where the `Module` column equals `$MODULE` AND the `Resolution` column equals `pending` (case-insensitive match on `pending`).

- **If pending > 0** → the update is **BLOCKED**. Print to the user verbatim:

  > Update `<UPDATE_DIR>` cannot be marked done — `<N>` pending PRD drift rows for module `$MODULE`:
  >
  > 1. `<conflict text from row 1>`
  > 2. `<conflict text from row 2>`
  > ...
  >
  > Resolve each by either:
  > - Running `/super-manus:prd-update $MODULE` (PRD edits to absorb the drift; the command flips the row's Resolution out of `pending`), OR
  > - Reverting the implementation to match PRD and editing the drift row's Resolution to `reverted` directly in `prd_drift.md` with a one-line note in `findings.md ## Decisions` explaining why.
  >
  > Then re-run `/super-manus:impl` to re-evaluate this gate.

  Do NOT flip the roadmap row to `stable`. Do NOT tell the user the update is complete. Do NOT continue to "Tell the user". STOP.

- **If pending == 0** → the update IS done. Update the module's row in `docs/super-manus/roadmap.md` from `iterating` to `stable`. Continue to "Tell the user".

### Gate is HARD

The agent must not soft-pass the update by reporting it complete while drift rows remain `pending`. There is no auto-resolve path; resolution always involves either `/super-manus:prd-update` or a manual `reverted` edit + findings entry.

## Tell the user

In one line: where you landed (which update / phase), what you did this turn (drafted plan via impl-architect / wrote code / closed phase / drift detected), and what they should do next (continue, run `/super-manus:prd-update`, or `/super-manus:sync` for a new milestone).
