# super-manus — Design Doc (v0.1)

> Validated through brainstorming session 2026-05-04.
> Status: design locked, ready to enter writing-plans.

## 1. What it is

**super-manus** — A Claude Code plugin fusing [obra/superpowers](https://github.com/obra/superpowers)' execution discipline with Manus-style ([OthmanAdi/planning-with-files](https://github.com/OthmanAdi/planning-with-files)) persistent file-based state.

**One-liner:** Survives `/clear`, generates dev-readable progress journals from git history, works alongside superpowers (not a fork).

## 2. Pain point (the "why")

`superpowers` provides TDD / subagent / code-review discipline but loses everything on `/clear` or `/compact`.
`planning-with-files` provides Manus-style persistent state across sessions but has no execution discipline.

**super-manus targets the gap:** persistent state that survives session boundaries, with hooks that auto-restore "where were we" without user babysitting.

It does NOT re-implement superpowers' executor. v0.1 is **persistence only**. Users keep using superpowers (or any other workflow) for execution; super-manus only owns the state layer.

## 3. Scope (v0.1)

**In:**
- Per-feature folder layout (parallel-feature safe)
- Three canonical persistent files per feature: `task_plan.md` / `findings.md` / `progress.md`
- On-demand per-phase implementation plans under `tasks/p<n>_impl.md` (lazy-created by `/super-manus:phase <n>`; planning-detail container only — not a TDD task spec)
- SessionStart hook: auto-restore active feature's `task_plan.md`
- SessionEnd hook: main agent writes session-level summary to `progress.md`
- PostToolUse hook on `git commit`: main agent writes one-line commit summary, updates phase status
- Slash commands: `/super-manus:start <name>` / `/super-manus:switch <name>` / `/super-manus:catchup` / `/super-manus:phase <n>` / `/super-manus:log`
- A `using-sm` skill that documents read/write conventions for the main agent

**Out (deferred to v0.2+):**
- TDD task executor (would consume `tasks/p<n>_impl.md` plus a runner; v0.1 only persists the planning file)
- Subagent dispatch
- Code review integration
- Git worktree integration
- Multi-harness (Codex / Cursor / Gemini) — Claude Code only for v0.1

## 4. File layout (project-side)

```
<project-root>/
├── .super-manus/
│   └── active                                  # text file: current feature folder name
└── docs/super-manus/
    └── <YYYY-MM-DD>-<feature-name>/
        ├── task_plan.md                        # goal / phases / status (LLM-maintained, index only — no code)
        ├── findings.md                         # research / decisions / errors (LLM-maintained)
        ├── progress.md                         # commit log + session summaries (LLM-written, structured)
        └── tasks/                              # phase-level implementation plans (lazy)
            └── p<n>_impl.md                         # one per active phase, created by /super-manus:phase <n> (v0.2 may add a runner)
```

### File responsibilities

| File | Owner | Updated when |
|---|---|---|
| `task_plan.md` | LLM | Phase boundaries (status changes, new phase added) |
| `findings.md` | LLM | Research finding, decision made, error logged |
| `progress.md` | LLM (via hooks) | Each `git commit`, each session end |
| `tasks/p<n>_impl.md` | LLM | Phase entered `in_progress` and needs an implementation plan; updated as approach evolves |
| `.super-manus/active` | `/super-manus:start` and `/super-manus:switch` commands | Feature created or switched |

### task_plan.md schema (minimal — it's the SessionStart-injected file)

```markdown
# Task Plan: <feature title>

## Goal
<one paragraph, immutable across the feature lifetime>

## Phases

| # | Name | Status | Notes |
|---|---|---|---|
| 1 | <phase> | closed | <one-line note> |
| 2 | <phase> | in_progress | <one-line note> |
| 3 | <phase> | pending | |
```

**Status values:** `pending` / `in_progress` / `blocked` / `closed`.
**No errors, decisions, or code here** — errors/decisions go in `findings.md`; per-phase implementation plans go in `tasks/p<n>_impl.md` (see §6 `/super-manus:phase`).

### findings.md schema (loose, free-form sections)

```markdown
# Findings: <feature title>

## Decisions
<dated entries: what was chosen, why, alternatives ruled out>

## Errors
| When | What failed | Resolution |
|---|---|---|

## Data points / research
<smoke results, evals, screenshots-converted-to-text, etc.>
```

### progress.md schema (structured, two LLM-written sections + one script-generated section)

```markdown
# Progress: <feature title>

## Completed commits  (D-trigger: written by main agent on each git commit)

- 2026-05-04 16:01 · `b1f1289` · closed P0
  按 subject 分流 fallback / validate；改 nodes.py，新增 6 测试。

- 2026-05-04 21:30 · `c906553` · advanced P1
  judge prompt 加 history 检测；P1 smoke 未跑。

## Session log  (B-trigger: written by main agent at SessionEnd)

### Session 2026-05-04 #2 (21:14 – 22:48)
- 完成 P1 prompt 修改 (c906553)
- 卡点：weak_quiet smoke 仍有 1 场死循环
- 下次会话先：手动跑 weak_quiet 单场 smoke

### Session 2026-05-04 #1 (14:32 – 16:05)
- 关闭 P0 (b1f1289)
- 决策：P0 走方案 A（findings.md §Decisions）

## Outstanding  (script-generated from task_plan.md)

- [P1] smoke 验证 (in_progress)
- [P2] follow-up 不被吞 (pending)
- [P3] 元话语清除 (pending)
- [P4] 类比保护 (pending)
```

### tasks/p<n>_impl.md schema (per-phase implementation plan, lazy)

```markdown
# Phase <n>: <phase name>

## Objective
<one paragraph: what "done" means for this phase, in plain English>

## Approach
<the chosen route: bullets, ordered steps, or short prose. Code snippets, pseudo-code, file diffs all live here, not in task_plan.md.>

## Files touched
- `path/to/file.py` — <one-line reason>

## Verification
<how you will know this phase is closed: tests to run, smoke command, manual check>
```

**Headings are stable** (`## Objective`, `## Approach`, `## Files touched`, `## Verification`) so future tooling can index them. The file is created on demand — phases that don't need a written plan can stay without one. `task_plan.md`'s Notes column may carry a relative link to the file (e.g. `tasks/p1_impl.md`) but is not required to.

## 5. Hooks (the runtime)

### Plugin layout

```
super-manus/
├── .claude-plugin/plugin.json
├── hooks/
│   ├── hooks.json
│   ├── run-hook.cmd                 # polyglot wrapper (borrowed pattern from superpowers)
│   ├── session-start                # catchup
│   ├── session-end                  # B-trigger: session summary
│   └── post-commit                  # D-trigger: commit summary
├── scripts/
│   ├── refresh-outstanding.sh       # regenerates "## Outstanding" section, no LLM
│   ├── sm-start.sh
│   ├── sm-switch.sh
│   └── sm-phase.sh                  # /super-manus:phase <n> — lazy-create tasks/p<n>_impl.md
├── commands/
│   ├── start.md                     # /super-manus:start <name>
│   ├── switch.md                    # /super-manus:switch <name>
│   ├── catchup.md                   # /super-manus:catchup (manual re-run of session-start logic)
│   ├── phase.md                     # /super-manus:phase <n> (open or seed a per-phase impl plan)
│   └── log.md                       # /super-manus:log (force-write a session log entry, reset counter)
├── skills/
│   └── using-sm/SKILL.md            # how to read/write the three files
├── templates/
│   ├── task_plan.md
│   ├── findings.md
│   ├── progress.md
│   └── phase_plan.md                # template for tasks/p<n>_impl.md
├── .claude-plugin/plugin.json
├── README.md
├── LICENSE                          # MIT (matches both upstream projects)
└── CLAUDE.md                        # contributor guide (PR governance for AI agents)
```

### hooks.json

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear|compact",
        "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" session-start", "async": false }]
      }
    ],
    "Stop": [
      {
        "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" session-end" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" post-commit" }]
      }
    ]
  }
}
```

### Hook behavior contracts

**`session-start`** (catchup)
- Read `.super-manus/active` → resolve current feature folder
- If no active feature: inject a small reminder ("no active super-manus feature; run `/super-manus:start <name>` to begin"). Do nothing else.
- If active: inject **only `task_plan.md` full text** + 1 line pointing to findings.md / progress.md paths.
- Token budget: ~500–1500 tokens depending on plan size.

**`session-end`** (B-trigger — runs on every Stop, but rate-limited)
- Stop hooks fire at the end of every agent reply, not just at session end. To avoid spamming `## Session log`, the hook keeps a per-feature counter at `<folder>/.session-state` (`<session_id> <turn-count>`) and only surfaces a checkpoint when one of two signals fires (governed by `SUPER_MANUS_LOG_MODE`, default `both`):
  - **turns** — count reaches `SUPER_MANUS_LOG_EVERY_N_TURNS` (default `5`)
  - **commit** — `## Completed commits` has an entry newer than the latest `### Session …` header in `## Session log`
- When surfaced, the hook returns `{"decision":"block","reason":text}` so the reminder actually reaches the model. Reason text asks the agent to **judge** whether the activity is worth a new line; if not, just stop. If yes, prepend a `### Session <date> #<n> (start–end)` block + 3 bullets (closed phases / blockers / next-session-first-action) and flip any newly blocked phase rows in `task_plan.md`.
- After the agent writes (or decides to skip), it tries to stop again; the hook receives `stop_hook_active=true` in stdin, resets the counter to 0, and exits no-op so the loop terminates.
- `/super-manus:log` is the manual escape hatch: force-write one entry, no judgment, also resets the counter.

**`post-commit`** (D-trigger)
- Detect `git commit` succeeded in the last Bash tool call (check exit code + command pattern)
- Inject system reminder: "git commit `<hash>` succeeded. Append one entry to `progress.md ## Completed commits`. If this commit closed a phase, update `task_plan.md` status to `closed`."
- Main agent does the write inline.

**`refresh-outstanding.sh`** (no hook, runs on demand or invoked by other hooks)
- Pure shell: parse `task_plan.md` Phases table, extract rows where status != closed
- Replace `## Outstanding` section in `progress.md`
- Zero LLM cost.

### Why hooks call main agent (not external LLM)

- No API key configuration required → plugin install is just `git clone` + Claude Code recognizes plugin.json
- Main agent already has feature context (it just wrote the commit message) → cheap and accurate
- Each hook injection is a few hundred tokens; total session overhead < 2k tokens

## 6. Commands

### `/super-manus:start <feature-name>`
- Validate `<feature-name>` (no spaces, lowercase-kebab-case)
- Compute folder path: `docs/super-manus/<TODAY>-<feature-name>/`
- If folder exists: error, suggest `/super-manus:switch`
- Otherwise: copy templates, write `.super-manus/active` with folder name
- Print confirmation + path

### `/super-manus:switch <feature-name>`
- List existing folders if `<feature-name>` ambiguous
- Match exact folder or unique substring
- Update `.super-manus/active`
- Trigger `session-start` hook logic to inject the new feature's `task_plan.md`

### `/super-manus:catchup`
- Manual re-run of `session-start` logic
- Useful when context drifted mid-session and main agent needs re-orientation
- No state change, just re-injection

### `/super-manus:phase <n>`
- Validate `<n>` is a positive integer matching a row in the active feature's `task_plan.md ## Phases` table
- Resolve target path: `<feature-folder>/tasks/p<n>_impl.md`
- If file exists: print its absolute path so the main agent can open it
- Otherwise: copy `templates/phase_plan.md`, substitute `<n>` and `<phase name>` (read from the Phases row), create `tasks/` parent dir as needed, then print the path
- No status mutation — entering `in_progress` is still the main agent's call via `task_plan.md` edit

### `/super-manus:log`
- Manual escape hatch when the user wants a `## Session log` entry now, regardless of the auto-trigger cadence
- Resolves the active feature, reads `<folder>/progress.md ## Completed commits`, prepends one entry to `## Session log` (no judgment / no skip — user explicitly asked)
- Resets `<folder>/.session-state` count to 0 so the next `SUPER_MANUS_LOG_EVERY_N_TURNS` window starts fresh
- No-op (with helpful message) if there is no active feature

## 7. The `using-sm` skill (the agent-facing protocol)

Single SKILL.md teaching the main agent:

1. **Where state lives** (the layout above)
2. **What goes in which file** (the schema rules)
3. **When to update each file**:
   - `task_plan.md`: phase status changes, new phase added
   - `findings.md`: any research finding, decision made (with reasoning), error encountered
   - `progress.md`: never directly — hooks handle it
4. **The 2-action rule** (borrowed from planning-with-files): after every 2 view/search ops, write key findings to `findings.md` before they're lost
5. **The 3-strike error protocol** (borrowed from planning-with-files): log every failure to `findings.md ## Errors`, mutate approach after 2 same-error attempts, escalate to user after 3
6. **Anti-patterns**: don't use TodoWrite for persistence (use task_plan.md), don't write progress.md directly, don't put errors in task_plan.md

## 8. Data flow (a typical session)

```
[User opens new session]
  ↓
SessionStart hook fires → reads .super-manus/active → injects task_plan.md
  ↓
Main agent picks up: "Currently on phase P1 (in_progress). Last commit closed P0."
  ↓
Main agent works, writes findings to findings.md as it discovers
  ↓
Main agent runs `git commit -m "..."` via Bash
  ↓
PostToolUse hook fires → injects "commit succeeded, update progress.md"
  ↓
Main agent appends to progress.md ## Completed commits, marks task_plan phase status if changed
  ↓
... more work, more commits ...
  ↓
[User runs /clear or session ends]
  ↓
Stop hook fires → injects "write session summary"
  ↓
Main agent appends to progress.md ## Session log
  ↓
Session ends; state is fully on disk
  ↓
[Next session]
  ↓
SessionStart hook fires again → injects task_plan.md (already up-to-date with closed phases) → main agent resumes seamlessly
```

## 9. Coexistence with superpowers

super-manus and superpowers can both be installed. They don't fight:

- super-manus owns: SessionStart / Stop / PostToolUse hooks (state layer)
- superpowers owns: SessionStart hook (skill bootstrap) — both fire, both inject, no conflict
- super-manus skills don't auto-trigger; only `using-sm` is invoked when user runs `/super-manus:*`
- Plans written by superpowers' writing-plans (`docs/plans/*.md`) are independent of super-manus' feature folders. User can keep using both: writing-plans for TDD execution plans, super-manus for cross-session feature state.

## 10. Distribution

- GitHub repo: `<user>/super-manus`
- License: MIT
- Marketplace: list on Claude Code plugin marketplace
- Docs: README with quickstart + 1 example feature folder
- Versioning: semver, v0.1.0 first release after dogfooding in teachagent

## 11. Risks and mitigations

| Risk | Mitigation |
|---|---|
| SessionEnd hook fires when context already compressed → main agent can't write good summary | Hook prompt explicitly says "re-read progress.md ## Completed commits before writing — those are the source of truth, not your memory" |
| post-commit hook misfires on non-`git commit` Bash calls | Hook script checks the actual command and exit code before injecting; no-op if not a successful commit |
| User has multiple super-manus features active in mental model but `.super-manus/active` only tracks one | v0.1 explicit limitation: single active feature. Multi-feature parallel work documented as v0.2 candidate. |
| `task_plan.md` grows huge → SessionStart injection bloats every new session | Document a "phase archive" pattern in `using-sm` skill: when phase count > 10, move closed phases to `findings.md ## Phase archive` and trim task_plan.md |
| Plugin breaks when superpowers updates SessionStart format | Hooks are independent; super-manus doesn't read superpowers' injection. No coupling. |

## 12. Success criteria for v0.1

The plugin is "v0.1 done" when, in teachagent's own development:

1. ✅ Run `/super-manus:start refactor-x` → folder created, templates filled
2. ✅ Work for an hour, make 2 commits → progress.md auto-populates with 2 commit lines
3. ✅ Run `/clear` → next message, main agent already knows current phase + recent commits without being told
4. ✅ Phase status in task_plan.md auto-updates when a closing commit lands
5. ✅ End session → progress.md gets a session log entry summarizing the hour
6. ✅ Next day, open new session → catchup works without reading anything manually

If 1–6 all work for one real feature in teachagent, ship as v0.1.0.

## 13. Out-of-scope clarifications (so reviewers don't ask)

- **No TDD enforcement** — `tasks/p<n>_impl.md` is a planning-detail file, not a TDD task spec. v0.2 may add an executor that consumes it; v0.1 only persists the file.
- **No subagent dispatch** — main agent does all writing
- **No automated test running** — that's the user's existing toolchain
- **No PR creation / merge integration** — separate concerns
- **No multi-language commit message parsing** — D-trigger reads commit hash + message verbatim, doesn't interpret
- **No conflict resolution if main agent writes progress.md and post-commit fires concurrently** — single-threaded by Claude Code's tool execution model
- **No auto-generation of phase plan content** — `/super-manus:phase <n>` only seeds the template; the Objective / Approach / etc. are filled by the main agent or user, consistent with v0.1's "persistence only" stance

## 14. Open questions deferred to implementation

- Exact wording of hook injection prompts (will iterate during implementation, not design-time)
- Template content for `task_plan.md` / `findings.md` / `progress.md` (draft during implementation)
- Whether `/super-manus:catchup` should also reload findings.md or stay task_plan.md only (likely task_plan.md only, but verify with usage)
- Cross-platform polyglot wrapper details for `run-hook.cmd` (port from superpowers verbatim)

## 15. Next steps after this design

1. User reviews this doc
2. Commit this design doc to teachagent repo
3. Use `superpowers:using-git-worktrees` to create isolated workspace for super-manus development (separate repo, not in teachagent)
4. Use `superpowers:writing-plans` to break this design into bite-sized implementation tasks
5. Implement v0.1 in the new repo
6. Dogfood in teachagent for one feature
7. Tag v0.1.0 → publish
