---
description: Run ONE phase end-to-end (architect → review → test-writer → review → code-writer → review → verify → close), then stop. If that was the last pending phase, run the end-of-update drift gate. Conservative default — one user invocation = one phase shipped. Optional `target` argument may be omitted, an update name, or a module name.
---

This is the v0.7 evolution of `/super-manus:impl`. Day-to-day execution entry. The user wants you to figure out where work is, draft the next phase's implementation plan if needed (delegated to the `impl-architect` subagent), check it against the module's PRD, write tests (delegated to `impl-test-writer`), write code (delegated to `impl-code-writer`), with `impl-reviewer` checkpoints between each writer stage and before phase close, then verify the phase, and stop.

The slash command is a **thin orchestrator**. It does NOT write phase plan content, tests, or source code itself; the four subagents own that. The orchestrator owns: target resolution, phase selection, drift checks, agent spawning + sequencing, the **3 review checkpoints with re-spawn loops**, the test-file hash check between test-writer and code-writer, the BLOCKING end-of-update drift gate, and phase-close verification.

Sister command: `/super-manus:impl-all` runs the same 4-agent pipeline but loops through ALL pending phases of the active update without pausing. This command stops after one phase. Use `impl-all` when you trust the breakdown and want to ship the milestone in one go; use `impl` when you want a checkpoint between phases.

## Resolve target

In v0.4/v0.5 there is no `.super-manus/active` state file — the PRD is project-global at `docs/super-manus/prd/`, and the active update is resolved purely by mtime scan via `sm_active_update` (sourced from `${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh`).

If `docs/super-manus/prd/` is not a directory, tell the user this project is not super-manus-enabled — they should run `/super-manus:start` first; then stop. If `docs/super-manus/impl/` is empty (no module subfolders), suggest `/super-manus:brainstorm` or `/super-manus:sync <module>`; then stop.

The user may pass an optional `target` argument:

- **Omitted** — use `sm_active_update` (no args; v0.4/v0.5 helper does not take arguments) to resolve the most recently modified update folder across all modules. The helper echoes `<module>/<update-name>`. If empty, suggest `/super-manus:sync <module>`.
- **Looks like a module name** (matches a `docs/super-manus/prd/<x>.md` file or a `docs/super-manus/roadmap.md` Module column entry) — find the most recently modified update folder under `docs/super-manus/impl/<target>/`. If none, suggest `/super-manus:sync <target>`.
- **Looks like an update folder name** (`<YYYY-MM-DD>-<name>`) — search `docs/super-manus/impl/*/<target>/`; if exactly one match, use it. If none, error and list candidates.

Heuristic: if `target` starts with a 4-digit year then dash, treat it as an update name. Otherwise treat as module.

Once resolved, set `UPDATE_DIR=docs/super-manus/impl/<module>/<update-name>` and `MODULE=<module>` for the rest of this run. Note: paths are project-global; there is no `<feature>/` prefix in v0.4/v0.5.

## Pick next phase

Read `$UPDATE_DIR/task_plan.md ## Phases` table. Find:

1. The first row whose Status is `in_progress` — that's where to continue. If absent, fall through.
2. The first row whose Status is `pending` — that's where to begin. Flip its Status to `in_progress` (one-line edit in task_plan.md).
3. If no `in_progress` and no `pending` phases remain, all phases are `closed` or `blocked`. Skip ahead to the **End-of-update drift gate** below — the gate decides whether the update is done. Do NOT short-circuit "all closed → done" without running the 3-pass gate.

Let `n` and `<phase name>` be the chosen row's `#` and `Name`.

## Drift check (BEFORE spending agent budget)

Run the **Drift check protocol** in [skills/using-sm/SKILL.md §4](../skills/using-sm/SKILL.md). The protocol is the shared LSP + grep cross-check used by `sync` / `impl` / `prd-update` / `reverse-prd` — this command consumes it before any agent is spawned.

The order is deliberate: drift check first (cheap), then the 3-agent pipeline (agent budget). If drift would block the work, we don't spend agent budget on a plan that will be discarded.

Concretely:

1. Read the per-module PRD `docs/super-manus/prd/<module>.md` (i.e. `docs/super-manus/prd/$MODULE.md`) — focus on `## What users get`, `## Quality bar`, `## Out of scope`.
2. Read the existing `$UPDATE_DIR/tasks/p<n>_impl.md ## Objective` if it already exists with substantive content; otherwise use the user's stated intent for this turn (and the phase Name from task_plan.md) as the proxy intent.
3. Apply the protocol against the phase intent. **LSP** (`document symbols` on the files the phase will touch; `find-references` on any cross-module export it touches) tells you whether the intent's capability already exists or is brand-new; **grep** covers wiring and quality-bar text LSP can't index. The double-source rule applies — only call drift when both LSP and grep (where applicable) agree the phase diverges from PRD.
4. If LSP is unavailable for this module's language, fall back per the protocol (grep + Read only) and surface "LSP unavailable — drift verdict is text-only inference" in the appended row's Conflict cell.

Decide: does the phase intent introduce a capability not declared in `## What users get`, or does it conflict with `## Out of scope` or violate `## Quality bar`?

- **No conflict** → continue to "Probe LSP availability".
- **Conflict** → append one row to `docs/super-manus/prd_drift.md` (project-global drift log, not per-feature):
  ```
  | <YYYY-MM-DD> | <module> | <one-line conflict description> | pending |
  ```
  Then tell the user: "Drift detected in phase <n> (`<phase-name>`) of `<module>`. Two paths:
  1. Revert the phase intent to match PRD `## What users get` / `## Quality bar` / `## Out of scope`.
  2. Run `/super-manus:prd-update $MODULE` first, then re-run `/super-manus:impl`."
  Stop. Do NOT proceed to spawning agents or writing code. The user must decide.

## Probe LSP availability once

Before spawning any agent, attempt one workspace-symbol call against the module to set `lsp_available=true|false`. Pass the boolean to all three agents so they can apply the protocol's fallback path correctly.

## Per-agent model override (v0.8.2)

For EVERY subagent spawn in this command (impl-architect / impl-reviewer at 3 checkpoints / impl-test-writer / impl-code-writer), before invoking the Agent tool, resolve the override model:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh"
override=$(sm_agent_model <agent-name>)
```

If `$override` is non-empty (one of `opus` / `sonnet` / `haiku`), pass `model: "$override"` to the Agent tool — this overrides the agent file's frontmatter. If empty (no entry, commented out, or no `.super-manus/agents.yml`), omit `model:` and let the agent's frontmatter apply: `opus` for thinkers (architect / reviewer / reverse-prd-architect), `inherit` for writers (test-writer / code-writer / sync-planner — they follow the main session's model unless `CLAUDE_CODE_SUBAGENT_MODEL` env var is set).

`effort:` is NOT routed through this file. Effort priority (high → low):

1. `CLAUDE_CODE_EFFORT_LEVEL` env var (highest — overrides everything)
2. Per-spawn parameter (Agent tool — not used by super-manus)
3. Frontmatter `effort:` (the plugin's `max` for thinkers / `high` for writers)
4. Model default

To globally cap effort across all super-manus agents, export `CLAUDE_CODE_EFFORT_LEVEL` in your shell. To override effort for one specific agent in one project without touching others, drop a copy of `agents/<name>.md` at `.claude/agents/<name>.md` (Claude Code prefers project-scope > plugin-scope).

## Step 1 — Spawn impl-architect

If no drift, the orchestrator delegates per-phase impl-plan drafting to the `impl-architect` subagent (Agent tool, `subagent_type="impl-architect"`). The agent owns the persona ("senior implementation planner"), the five-section template population (v0.9.0: `## Objective`, `## Approach`, `## Edge cases`, `## Files touched`, `## Verification`), and the source-priority hierarchy. Do NOT inline that persona here — see [agents/impl-architect.md](../agents/impl-architect.md).

Why a subagent: phase-plan drafting needs LSP + grep budget on the module's entry files plus a focused PM/engineering voice. Embedding it in the main thread bloats orchestrator context and fragments the persona.

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
- `prior_reflections` — verbatim contents of `$UPDATE_DIR/findings.md ## Reflections` if non-empty (heuristics from prior phases of THIS update); absent / empty if no prior reflections exist. Read the section once before the first spawn of this phase; reuse the same value on any re-spawn within this phase.

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
> - prior_reflections: `<verbatim ## Reflections section text, or "(none)" if empty>`
>
> Draft (or resume) `${update_dir}/tasks/p<n>_impl.md` per your agent definition. If `prior_reflections` is non-empty, treat each Heuristic line as a checklist item to honor in this phase's `## Approach` and `## Files touched`. Return the summary line when done.

The agent writes `$UPDATE_DIR/tasks/p<n>_impl.md` directly via the Write/Edit tools, seeding from `${CLAUDE_PLUGIN_ROOT}/templates/phase_plan.md` if the file does not yet exist (the template carries the five stable headings `## Objective` / `## Approach` / `## Edge cases` / `## Files touched` / `## Verification` — `## Edge cases` was added in v0.9.0 to lift "test coverage" from "did test-writer remember?" to an architect-committed checklist). It does NOT print the file to chat and it does NOT write code. If the file already has substantive content in all five sections, it is idempotent — it returns "phase plan already drafted; resume from existing" and the orchestrator continues. If the file exists with the legacy 4-section shape (no `## Edge cases`), the architect inserts the section in place and returns "migrated legacy plan; added Edge cases section".

### After the architect returns

The orchestrator MUST:

1. Verify `$UPDATE_DIR/tasks/p<n>_impl.md` exists and has non-empty `## Objective`, `## Approach`, `## Edge cases`, `## Files touched`, `## Verification` sections (5 sections, v0.9.0).
2. If any of the five headings is missing or empty, surface a one-line warning to the user ("impl-architect produced an incomplete plan; please review tasks/p<n>_impl.md before continuing") — do NOT silently fix.
3. Surface the agent's summary line verbatim to the user.
4. **Migration handling (v0.9.0).** If the architect's summary line begins with `migrated legacy plan; added Edge cases section`, surface an extra one-line warning to the user **before proceeding to Step 2 (impl-reviewer pre-test)**: `"⚠ legacy 4-section plan migrated to 5-section shape; please review the newly-inserted ## Edge cases section in tasks/p<n>_impl.md before tests are written — it was drafted by the architect without your prior approval of those edges."` Do NOT skip pre-test review on a migrated plan; the reviewer's enumeration check is exactly what we want to catch a hastily-inserted section.

Engineering detail (DB schema, API endpoints, code snippets, file diffs) lives in this phase plan — NOT in the per-module PRD. The PRD answered "this module IS what"; this phase plan answers "this phase DOES what".

## Step 2 — Spawn impl-reviewer (mode=pre-test) [v0.7]

Before spending test-writer + code-writer budget, the orchestrator spawns `impl-reviewer` (Agent tool, `subagent_type="impl-reviewer"`) in `pre-test` mode to check whether the architect's plan is grounded in real data and free of unresolved `(audit)` markers. The reviewer is read-only by tool surface (no Write/Edit) and emits one of three verdicts. See [agents/impl-reviewer.md](../agents/impl-reviewer.md) for the persona and per-mode checklist.

### Inputs to pass

Same inputs as architect (`project_root`, `module`, `update_dir`, `phase_number`, `phase_name`, `module_prd_path`, `index_prd_path`, `task_plan_path`, `phase_plan_path`, `findings_path`, `lsp_available`) plus:

- `mode` — `pre-test`
- `attempt_number` — `1` on first invocation; incremented on re-spawn after RETURN

### Spawning prompt skeleton

> Inputs from /super-manus:impl orchestrator (review checkpoint #1):
>
> - mode: `pre-test`
> - attempt_number: `<1|2|3>`
> - project_root: `<absolute path>`
> - module: `<module>`
> - update_dir: `<absolute path>`
> - phase_number: `<n>`
> - phase_name: `<name>`
> - module_prd_path: `<absolute path>`
> - index_prd_path: `<absolute path>`
> - task_plan_path: `<absolute path>`
> - phase_plan_path: `<absolute path>`
> - findings_path: `<absolute path>`
> - lsp_available: `<true|false>`
>
> Run pre-test review per your agent definition. Return ONE of: APPROVE, RETURN_TO_ARCHITECT, ESCALATE_TO_USER.

### Verdict handling

Track per-checkpoint counter `counter[#1]` (resets per phase, NOT per attempt). Initialize to 0. On verdict:

- **APPROVE** → continue to Step 3 (test-writer). Optionally surface reviewer's `notes` block to user as informational.
- **RETURN_TO_ARCHITECT** → increment `counter[#1]`. If `counter[#1] > 2`, fall through to ESCALATE handling below. Otherwise:
  1. Append the reviewer's full verdict block as a row to `$UPDATE_DIR/findings.md ## Errors`:
     ```
     | <YYYY-MM-DD> | review #1 attempt <N> RETURN_TO_ARCHITECT | <issues summary>; suggested: <suggested_actions summary> |
     ```
  2. Re-spawn `impl-architect` (Step 1) with same inputs PLUS a `previous_attempt_feedback` block in the prompt containing the reviewer's `issues` and `suggested_actions` verbatim.
  3. After architect re-emits the plan, re-invoke this Step 2 review with `attempt_number = counter[#1] + 1`.
- **ESCALATE_TO_USER** (or counter exhausted) → stop the phase. Append the escalation history to `findings.md ## Errors`. Surface to user verbatim:

  > Phase <n> stopped at review checkpoint #1 (pre-test) after <N> attempts. Reviewer's final verdict:
  > <full ESCALATE_TO_USER block>
  >
  > User options:
  > <reviewer's user_options>
  >
  > Next: edit the plan / PRD / phase row manually, or revise scope, then re-run /super-manus:impl.

  Phase Status stays `in_progress`. Do NOT proceed to test-writer.

## Step 3 — Spawn impl-test-writer

After review #1 APPROVES, the orchestrator spawns the `impl-test-writer` subagent (Agent tool, `subagent_type="impl-test-writer"`). The agent owns the persona ("senior test engineer"), the read-priority hierarchy, the e2e decision tree, and the per-language naming conventions. Do NOT inline that persona here — see [agents/impl-test-writer.md](../agents/impl-test-writer.md).

Why a subagent: tests anchored in PRD spec (not impl plan) need a distinct persona from the planner. Splitting the persona prevents the architect's `## Approach` framing from leaking into test structure.

### Inputs to pass in the spawning prompt

Pass these in the Agent tool's `prompt` field:

- `project_root` — current working directory absolute path
- `module` — `$MODULE`
- `update_dir` — `$UPDATE_DIR` absolute path
- `phase_number` — `n`
- `phase_name` — the row's Name cell, verbatim
- `module_prd_path` — `docs/super-manus/prd/<module>.md` absolute path
- `index_prd_path` — `docs/super-manus/prd/_index.md` absolute path
- `task_plan_path` — `$UPDATE_DIR/task_plan.md`
- `e2e_dir` — `docs/super-manus/e2e/` absolute path
- `lsp_available` — `true` or `false`
- `prior_tests_glob` — comma-separated globs (`$UPDATE_DIR/tests/phase_*`, `docs/super-manus/e2e/<module>/test_*`, `docs/super-manus/e2e/_system/test_*`)

### Spawning prompt skeleton

> Inputs from /super-manus:impl orchestrator:
>
> - project_root: `<absolute path>`
> - module: `<module>`
> - update_dir: `<absolute path>`
> - phase_number: `<n>`
> - phase_name: `<name>`
> - module_prd_path: `<absolute path>`
> - index_prd_path: `<absolute path>`
> - task_plan_path: `<absolute path>`
> - e2e_dir: `<absolute path>`
> - lsp_available: `<true|false>`
> - prior_tests_glob: `<comma-separated globs>`
>
> Write phase tests + e2e tests (red) per your agent definition. Commit ONLY test files. Return the summary line when done.

The agent writes:

- (a) `$UPDATE_DIR/tests/phase_p<n>_*.{ext}` — always.
- (b) `docs/super-manus/e2e/<module>/test_<capability>.{ext}` — when this phase completes a `## What users get` capability.
- (c) `docs/super-manus/e2e/_system/test_<scenario>.{ext}` — when this phase completes a cross-module `## Demo` scenario.

The agent commits ONLY test files. The orchestrator will reject (and abort the phase) if the commit touches anything else.

### After the test-writer returns

1. Verify the commit touches only paths under `$UPDATE_DIR/tests/` and `docs/super-manus/e2e/`. If any source file was touched, ABORT — append a `test-writer touched non-test files` row to `prd_drift.md` and surface to user.
2. Surface the agent's summary line verbatim.

(Hash baseline is established AFTER review #2 APPROVES — see Step 5.)

## Step 4 — Spawn impl-reviewer (mode=pre-code) [v0.7]

After the test-writer commits red tests, the orchestrator spawns `impl-reviewer` in `pre-code` mode to verify fixtures use real data (not inline dicts derived from architect's plan), tests cover all declared inputs, and tests are not vacuous (passing before code exists).

### Inputs to pass

Same as Step 2 but with `mode = pre-code` and one additional input:

- `phase_tests_glob` — `$UPDATE_DIR/tests/phase_p<n>_*.{ext}`
- `e2e_tests_glob` — comma-separated globs covering touched e2e files (extracted from the test-writer's commit)

### Spawning prompt skeleton

> Inputs from /super-manus:impl orchestrator (review checkpoint #2):
>
> - mode: `pre-code`
> - attempt_number: `<1|2|3>`
> - project_root: `<absolute path>`
> - module: `<module>`
> - update_dir: `<absolute path>`
> - phase_number: `<n>`
> - phase_name: `<name>`
> - module_prd_path: `<absolute path>`
> - index_prd_path: `<absolute path>`
> - task_plan_path: `<absolute path>`
> - phase_plan_path: `<absolute path>`
> - phase_tests_glob: `<glob>`
> - e2e_tests_glob: `<comma-separated globs>`
> - findings_path: `<absolute path>`
> - lsp_available: `<true|false>`
>
> Run pre-code review per your agent definition. Return ONE of: APPROVE, RETURN_TO_TEST_WRITER, RETURN_TO_ARCHITECT, ESCALATE_TO_USER.

### Verdict handling

Track per-checkpoint counter `counter[#2]`. Initialize to 0.

- **APPROVE** → continue to Step 5 (hash baseline + spawn code-writer).
- **RETURN_TO_TEST_WRITER** → increment `counter[#2]`. If `counter[#2] > 2`, ESCALATE. Otherwise:
  1. Append verdict to `findings.md ## Errors`.
  2. Re-spawn `impl-test-writer` (Step 3) with `previous_attempt_feedback` block.
  3. After test-writer re-commits, re-invoke this Step 4 review with `attempt_number = counter[#2] + 1`.
- **RETURN_TO_ARCHITECT** → increment `counter[#2]`. If `counter[#2] > 2`, ESCALATE. Otherwise:
  1. Append verdict to `findings.md ## Errors`.
  2. Re-spawn `impl-architect` (Step 1) with `previous_attempt_feedback`. (Counter at #1 does NOT increment — this is checkpoint #2's RETURN, even if it cascades upstream.)
  3. After architect re-emits, re-spawn `impl-test-writer` (Step 3) — fresh attempt, counter[#1] AND #2 both apply to their own checkpoints.
  4. Re-invoke Step 2 review (with `counter[#1]` reset to 0 since plan is fresh — but reuse history from prior attempts in findings.md).
  5. If Step 2 APPROVES, fall through to Step 3 (test-writer), then re-invoke this Step 4 review with `attempt_number = counter[#2] + 1`.
- **ESCALATE_TO_USER** (or counter exhausted) → stop the phase as in Step 2's ESCALATE handling. Phase Status stays `in_progress`.

## Step 5 — Hash baseline + spawn impl-code-writer

After review #2 APPROVES, the orchestrator FIRST establishes the hash baseline on the test files that just passed review:

```bash
git diff --name-only HEAD~1 HEAD | while read p; do
  case "$p" in
    "$UPDATE_DIR/tests/"*|"docs/super-manus/e2e/"*)
      sha256sum "$p" >> "$UPDATE_DIR/.test_hashes_p<n>.txt"
      ;;
  esac
done
```

Keep the hash file in `$UPDATE_DIR` so cascade re-spawn (e.g., RETURN_TO_TEST_WRITER from review #3) can reload it after the new test commit. **The hash baseline always reflects the latest reviewer-approved test commit.** When test-writer is re-spawned and re-commits, this Step 5 reruns and the baseline is refreshed.

Then spawn the `impl-code-writer` subagent (Agent tool, `subagent_type="impl-code-writer"`). The agent owns the persona ("senior implementation engineer"), the iteration loop, and the hard rule that NO test files may be edited. Do NOT inline that persona here — see [agents/impl-code-writer.md](../agents/impl-code-writer.md).

### Inputs to pass in the spawning prompt

Pass these in the Agent tool's `prompt` field:

- `project_root` — current working directory absolute path
- `module` — `$MODULE`
- `update_dir` — `$UPDATE_DIR` absolute path
- `phase_number` — `n`
- `phase_name` — the row's Name cell, verbatim
- `module_prd_path` — `docs/super-manus/prd/<module>.md` absolute path
- `task_plan_path` — `$UPDATE_DIR/task_plan.md`
- `phase_plan_path` — `$UPDATE_DIR/tasks/p<n>_impl.md`
- `phase_tests_glob` — `$UPDATE_DIR/tests/phase_p<n>_*.{ext}`
- `e2e_tests_glob` — comma-separated globs covering touched e2e files (extracted from the test-writer's commit)
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
> - phase_plan_path: `<absolute path>`
> - phase_tests_glob: `<glob>`
> - e2e_tests_glob: `<comma-separated globs>`
> - lsp_available: `<true|false>`
>
> Write source code to make all phase tests + touched e2e tests pass per your agent definition. Do NOT touch any file under `tests/` or `docs/super-manus/e2e/`. Commit ONLY source files. Return the summary line when done.

The agent iterates source-code → run tests → repeat until all green, then commits source files only and returns. The agent may also return early in **stuck state** ("tests un-passable") — surface that state to review #3 in Step 6 below.

## Step 6 — Spawn impl-reviewer (mode=pre-close) [v0.7]

After the code-writer returns (whether green or stuck), the orchestrator spawns `impl-reviewer` in `pre-close` mode to verify the implementation matches the plan, touches only declared files, has no security smells, and (if code-writer reported stuck) to diagnose whether the test, the plan, or the code is the root cause.

### Inputs to pass

Same as Step 4 plus:

- `mode` — `pre-close`
- `code_writer_stuck` — `true` if code-writer returned with "tests un-passable" / similar; `false` if code-writer reported all tests green

### Spawning prompt skeleton

> Inputs from /super-manus:impl orchestrator (review checkpoint #3):
>
> - mode: `pre-close`
> - attempt_number: `<1|2|3>`
> - code_writer_stuck: `<true|false>`
> - project_root: `<absolute path>`
> - module: `<module>`
> - update_dir: `<absolute path>`
> - phase_number: `<n>`
> - phase_name: `<name>`
> - module_prd_path: `<absolute path>`
> - task_plan_path: `<absolute path>`
> - phase_plan_path: `<absolute path>`
> - phase_tests_glob: `<glob>`
> - e2e_tests_glob: `<comma-separated globs>`
> - findings_path: `<absolute path>`
> - lsp_available: `<true|false>`
>
> Run pre-close review per your agent definition. Return ONE of: APPROVE, RETURN_TO_CODE_WRITER, RETURN_TO_TEST_WRITER, RETURN_TO_ARCHITECT, ESCALATE_TO_USER.

### Verdict handling

Track per-checkpoint counter `counter[#3]`. Initialize to 0.

- **APPROVE** → continue to Step 7 (hash check, then verification).
- **RETURN_TO_CODE_WRITER** → increment `counter[#3]`. If `counter[#3] > 2`, ESCALATE. Otherwise:
  1. Append verdict to `findings.md ## Errors`.
  2. Re-spawn `impl-code-writer` (Step 5) with `previous_attempt_feedback`. (No hash refresh — tests unchanged.)
  3. After code-writer re-commits (or returns stuck again), re-invoke this Step 6 review with `attempt_number = counter[#3] + 1`.
- **RETURN_TO_TEST_WRITER** → increment `counter[#3]`. If `counter[#3] > 2`, ESCALATE. Otherwise:
  1. Append verdict to `findings.md ## Errors`.
  2. Re-spawn `impl-test-writer` (Step 3) with `previous_attempt_feedback`.
  3. After test-writer re-commits, **re-run Step 4 (review #2 pre-code)** to validate the new tests with `counter[#2]` reset to 0 (fresh tests = fresh checkpoint state at #2; #3's history persists).
  4. If review #2 APPROVES, refresh hash baseline (Step 5) and re-spawn code-writer (Step 5).
  5. After code-writer returns, re-invoke this Step 6 review with `attempt_number = counter[#3] + 1`.
- **RETURN_TO_ARCHITECT** → increment `counter[#3]`. If `counter[#3] > 2`, ESCALATE. Otherwise:
  1. Append verdict to `findings.md ## Errors`.
  2. Re-spawn `impl-architect` (Step 1) with `previous_attempt_feedback`. (Counters #1 and #2 reset to 0 — plan + tests are fresh.)
  3. Cascade through Steps 2 → 3 → 4 → 5 → return here for re-invocation with `attempt_number = counter[#3] + 1`.
- **ESCALATE_TO_USER** (or counter exhausted) → stop the phase. Append the escalation history to `findings.md ## Errors`. Phase Status stays `in_progress`. Surface to user verbatim per Step 2's ESCALATE template.

## Step 7 — Hash check (cheat-prevention)

After the code-writer returns, re-hash every test file recorded in `.test_hashes_p<n>.txt` and compare:

```bash
while read line; do
  expected_hash=$(echo "$line" | awk '{print $1}')
  path=$(echo "$line" | awk '{print $2}')
  actual_hash=$(sha256sum "$path" | awk '{print $1}')
  [ "$expected_hash" != "$actual_hash" ] && echo "TAMPER: $path"
done < "$UPDATE_DIR/.test_hashes_p<n>.txt"
```

- **All hashes match** → continue to step 5 (verification).
- **Any mismatch** → ABORT this phase. The phrase "code-writer modified tests" applies. Append a row to `docs/super-manus/prd_drift.md`:

  ```
  | <YYYY-MM-DD> | <module> | code-writer modified tests for phase p<n> | pending |
  ```

  Surface to the user verbatim:

  > ABORTED phase <n>: the code-writer modified <N> test file(s). Drift row appended. Resolve by either reverting the code-writer's commits and re-running `/super-manus:impl`, or accepting the test changes via a manual review (then re-run).

  Do NOT flip the phase status. Do NOT continue to verification. STOP.

## Step 8 — Verification (orchestrator runs `## Verification`)

If hashes match, the orchestrator (NOT the code-writer) runs every command in `$UPDATE_DIR/tasks/p<n>_impl.md ## Verification`. See [skills/verification-before-phase-close/SKILL.md](../skills/verification-before-phase-close/SKILL.md) for the run protocol.

For each bullet:

1. Print the command verbatim before running.
2. Run it. Capture exit code.
3. If exit code 0 AND output matches the stated observable → mark ok.
4. If exit code non-zero OR observable does not match → invoke the [systematic-debugging-in-phase](../skills/systematic-debugging-in-phase/SKILL.md) skill. Phase stays `in_progress`. Do NOT flip to `closed`.

For manual bullets (`open URL, click X`), prompt the user once to confirm the observable was seen.

## Step 9 — Phase close

When ALL `## Verification` commands pass:

1. **Synthesize phase reflection (Reflexion-style cross-phase memory).** Read `$UPDATE_DIR/findings.md ## Errors` and count rows whose When-or-What cell mentions this phase (e.g., `phase p<n>` or `review #1/#2/#3 attempt <N>` rows the orchestrator wrote during this phase's RETURN handling). Two cases:
   - **Zero RETURN rows for this phase** — the phase was clean on first try. Skip this step entirely; do NOT write an empty entry.
   - **One or more RETURN rows for this phase** — synthesize a single H3 entry and append it to `$UPDATE_DIR/findings.md ## Reflections` (orchestrator main thread does this inline; no agent spawn). Exact shape:

     ```markdown
     ### Phase <n>: <phase_name>
     - Misstep: <one sentence — what attempt 1 got wrong; the surface event from ## Errors row 1>
     - Root cause: <one sentence — why the writer made that choice; inferred from reviewer's `issues` text>
     - Heuristic: <one sentence — rule for next phase to avoid this; this is the load-bearing line>
     ```

     Voice rules (load-bearing — keep distinct from `## Errors` and `## Session log`):
     - Misstep is the surface event; Root cause is causal; **Heuristic is prescriptive** ("Run head -1 on every declared input source before drafting ## Approach", not "we re-fixtured tests on real data").
     - If the Heuristic line reads as a recap of what happened rather than a rule for next time, rewrite it.
     - Three bullets, no more. No code, no file paths, no function names, no test commands — same hygiene as `findings.md ## Decisions`.
     - Append (not prepend) so phase order matches reading order.
2. Edit `task_plan.md ## Phases` to flip the phase row's Status from `in_progress` to `closed`.
3. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/refresh-outstanding.sh" "$UPDATE_DIR"` to regenerate `progress.md ## Outstanding`.
4. Delete the temporary `$UPDATE_DIR/.test_hashes_p<n>.txt` file (it served its purpose).

The post-commit hook automatically appends commit lines to `$UPDATE_DIR/progress.md ## Completed commits`. Do **not** hand-edit `progress.md` — it is hook-managed.

The synthesis step (1) deliberately runs AFTER the cheat-prevention hash check (Step 7) and `## Verification` (Step 8), so a phase that aborts early writes no reflection — only successfully closed phases contribute to the cross-phase memory.

## Terminal behavior — the differentiator from `/super-manus:impl-all`

Re-read `task_plan.md ## Phases` and count rows where Status is `pending` (excluding the one just closed):

- **More pending phases remain** → STOP. Tell the user:
  > Phase <n> (`<phase-name>`) shipped. Next pending phase: phase <m> (`<next-phase-name>`). Re-run `/super-manus:impl` to continue, or `/super-manus:impl-all` to ship the rest of the milestone in one go.

  Do NOT auto-loop. The user controls the loop boundary in `/super-manus:impl`. This is the deliberate difference from `/super-manus:impl-all`.

- **No pending phases remain** → fall through to the **End-of-update drift gate** below.

## End-of-update drift gate (BLOCKING — 3-pass in v0.5)

When all phases in `$UPDATE_DIR/task_plan.md` are `closed`, the update is **NOT done** until all three passes succeed. The gate is BLOCKING. Pending == 0 is the required condition to flip the roadmap from `iterating` to `stable`.

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

### Pass 2 — e2e coverage check (NEW in v0.5)

For each `## What users get` capability touched by this update's commits:

1. Verify `docs/super-manus/e2e/<module>/test_<capability>.{ext}` exists.
2. Run it. It must pass.
3. Missing → append a `pending` row:
   ```
   | <YYYY-MM-DD> | $MODULE | missing e2e coverage for capability <capability> | pending |
   ```
4. Red → append a `pending` row:
   ```
   | <YYYY-MM-DD> | $MODULE | e2e for capability <capability> is red | pending |
   ```

For each cross-module `## Demo` scenario completed in this update:

1. Verify `docs/super-manus/e2e/_system/test_<scenario>.{ext}` exists and passes.
2. Same `pending` rules.

Pass 2 violations are resolved by re-spawning `impl-test-writer` in `e2e_only` mode (the user re-runs `/super-manus:impl` and the orchestrator spots the missing e2e in the gate, suggests writing it). Or the user resolves manually.

### Pass 3 — Block until pending == 0

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
  > - Reverting the implementation to match PRD and editing the drift row's Resolution to `reverted` directly in `prd_drift.md` with a one-line note in `findings.md ## Decisions` explaining why, OR
  > - Writing the missing e2e test (for Pass 2 violations) and re-running `/super-manus:impl`.
  >
  > Then re-run `/super-manus:impl` to re-evaluate this gate.

  Do NOT flip the roadmap row to `stable`. Do NOT tell the user the update is complete. STOP.

- **If pending == 0** → the update IS done. Update the module's row in `docs/super-manus/roadmap.md` from `iterating` to `stable`. Continue to "Tell the user".

### Gate is HARD

The agent must not soft-pass the update by reporting it complete while drift rows remain `pending`. There is no auto-resolve path; resolution always involves either `/super-manus:prd-update`, a manual `reverted` edit + findings entry, or writing the missing e2e (for Pass 2).

## Tell the user

In one line: where you landed (which update / phase), what you did this turn (drafted plan via impl-architect / wrote tests via impl-test-writer / wrote code via impl-code-writer / verified / closed phase / drift detected / gate blocked), and what they should do next (re-run `/super-manus:impl` to ship the next phase, run `/super-manus:impl-all` to finish the milestone, run `/super-manus:prd-update`, or `/super-manus:sync` for a new milestone).
