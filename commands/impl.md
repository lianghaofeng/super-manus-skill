---
description: Resume / advance work in the active milestone-update; auto-selects next pending phase, seeds tasks/p<n>_impl.md, runs PRD drift check, then executes
---

This is the v0.2 successor to `/super-manus:phase`. Day-to-day execution entry. The user wants you to figure out where work is, draft the next phase's implementation plan if needed, check it against the module's PRD, and continue executing.

## Resolve target

Read `.super-manus/active`. The folder is `docs/super-manus/<that-name>/`. If missing or empty, tell the user there is no active feature and suggest `/super-manus:start <name>`; then stop.

If `<feature>/prd/` is not a directory (legacy v0.1), tell the user `/super-manus:impl` is v0.2-only — they should keep using `/super-manus:phase <n>` for v0.1 features. Then stop.

The user may pass a `target` argument:

- **Omitted** — use `sm_active_update <feature>` (sourced from `${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh`) to resolve the most recently modified update folder across all modules. If empty, suggest `/super-manus:brainstorm` or `/super-manus:sync <module>`.
- **Looks like a module name** (matches a `prd/<x>.md` file or a `roadmap.md` Module column entry) — find the most recently modified update folder under `<feature>/impl/<target>/`. If none, suggest `/super-manus:sync <target>`.
- **Looks like an update folder name** (`<YYYY-MM-DD>-<name>`) — search `<feature>/impl/*/<target>/`; if exactly one match, use it. If none, error and list candidates.

Heuristic: if `target` starts with a 4-digit year then dash, treat it as an update name. Otherwise treat as module.

Once resolved, set `UPDATE_DIR=<feature>/impl/<module>/<update-name>` and `MODULE=<module>` for the rest of this run.

## Pick next phase

Read `$UPDATE_DIR/task_plan.md ## Phases` table. Find:

1. The first row whose Status is `in_progress` — that's where to continue. If absent, fall through.
2. The first row whose Status is `pending` — that's where to begin. Flip its Status to `in_progress` (one-line edit in task_plan.md).
3. If no `in_progress` and no `pending` phases remain, all phases are `closed` or `blocked`. Tell the user the update is complete (or blocked) and suggest:
   - `/super-manus:sync <module>` to start a new update for this module
   - `/super-manus:drive` to scan the whole feature for the next thing to do
   Stop.

Let `n` and `<phase name>` be the chosen row's `#` and `Name`.

## Seed `tasks/p<n>_impl.md` if missing

If `$UPDATE_DIR/tasks/p<n>_impl.md` does NOT exist, create it from the template:

```bash
sed -e "s|<n>|<n>|g" -e "s|<phase name>|<phase-name>|g" \
  "${CLAUDE_PLUGIN_ROOT}/templates/phase_plan.md" > "$UPDATE_DIR/tasks/p<n>_impl.md"
```

(The agent does this via the Bash tool.) The file has stable headings `## Objective` / `## Approach` / `## Files touched` / `## Verification`. Leave them empty for the agent to draft below.

If the file already exists, leave it untouched (idempotent).

## Drift check (BEFORE drafting impl plan or writing code)

Run the **Drift check protocol** in [skills/using-sm/SKILL.md §4](../skills/using-sm/SKILL.md). The protocol is the shared LSP + grep cross-check used by `sync` / `impl` / `prd-update` / `reverse-prd` — this command consumes it before any code is drafted.

Concretely:

1. Read the per-module PRD `<feature>/prd/<module>.md` (i.e. `<feature>/prd/$MODULE.md`) — focus on `## Surface`, `## Constraints`, `## Out of scope`.
2. Read the just-seeded or already-existing `$UPDATE_DIR/tasks/p<n>_impl.md ## Objective` (if non-empty), and the user's stated intent for this turn.
3. Apply the protocol against the phase intent. **LSP** (`document symbols` on the files the phase will touch; `find-references` on any cross-module export it touches) tells you whether the intent's surface already exists or is brand-new; **grep** covers wiring and constraints LSP can't index. The double-source rule applies — only call drift when both LSP and grep (where applicable) agree the phase diverges from PRD.
4. If LSP is unavailable for this module's language, fall back per the protocol (grep + Read only) and surface "LSP unavailable — drift verdict is text-only inference" in the appended row's Conflict cell.

Decide: does the phase intent introduce a capability not declared in `## Surface`, or does it conflict with `## Out of scope`?

- **No conflict** → continue.
- **Conflict** → append one row to `<feature>/prd_drift.md`:
  ```
  | <YYYY-MM-DD> | <module> | <one-line conflict description> | pending |
  ```
  Then tell the user: "Drift detected in phase <n> (`<phase-name>`) of `<module>`. Two paths:
  1. Revert the phase intent to match PRD `## Surface` / `## Constraints` / `## Out of scope`.
  2. Run `/super-manus:prd-update $MODULE` first, then re-run `/super-manus:impl`."
  Stop. Do NOT proceed to drafting code or `## Approach`. The user must decide.

## Draft / advance the impl plan

If no drift, draft `$UPDATE_DIR/tasks/p<n>_impl.md` (filling in `## Objective`, `## Approach`, `## Files touched`, `## Verification`) per the using-sm skill conventions. If the file already has substantive content, just continue from where it left off.

Engineering detail (DB schema, API endpoints, code snippets, file diffs) lives here — NOT in the per-module PRD. The PRD answered "this module IS what"; this phase plan answers "this phase DOES what".

## Execute

After drafting / confirming the plan, proceed to writing code per the standard execution flow (TDD where applicable, edits, commits). The post-commit hook will append commit lines to `$UPDATE_DIR/progress.md`. Do **not** hand-edit `progress.md` — it's hook-managed.

When a phase is verified done, flip its row in `$UPDATE_DIR/task_plan.md` to `closed`. After flipping, run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/refresh-outstanding.sh" "$UPDATE_DIR"
```

to regenerate `progress.md ## Outstanding`.

## End-of-update consistency check

When all phases in `$UPDATE_DIR/task_plan.md` are `closed`, read `<feature>/prd/$MODULE.md` and `$UPDATE_DIR/progress.md ## Completed commits`. Report two diffs to the user:

- "PRD declared but not implemented" — bullets in `## Surface` / `## Constraints` not reflected by any commit.
- "Implemented but not in PRD" — capabilities visible in commits but not declared in PRD; for each, append one row to `prd_drift.md` and prompt for `/super-manus:prd-update $MODULE`.

Do not silently flip the module to `stable` in roadmap if drift remains unresolved. Once both diffs are empty (or all drift rows have non-`pending` Resolutions), update the module's row in `<feature>/roadmap.md` from `iterating` to `stable`.

## Tell the user

In one line: where you landed (which update / phase), what you did this turn (drafted plan / wrote code / closed phase / drift detected), and what they should do next (continue, run `/super-manus:prd-update`, or `/super-manus:sync` for a new milestone).
