# super-manus

*Survives `/clear`, generates dev-readable progress journals from git history, works alongside superpowers (not a fork).*

## What

**super-manus** is a Claude Code plugin that fuses [obra/superpowers](https://github.com/obra/superpowers)' execution discipline with Manus-style ([OthmanAdi/planning-with-files](https://github.com/OthmanAdi/planning-with-files)) persistent file-based state. It owns the state layer only: a per-feature folder on disk holds your task plan, findings, and progress journal, and hooks keep them in sync as you work.

## Why

`superpowers` gives you TDD, subagent dispatch, and code-review discipline, but loses everything on `/clear` or `/compact`. `planning-with-files` gives you Manus-style persistent state across sessions, but no execution discipline.

super-manus targets the gap: persistent state that survives session boundaries, with hooks that auto-restore "where were we" without user babysitting. It does NOT re-implement superpowers' executor — v0.1 is **persistence only**. Keep using superpowers (or any other workflow) for execution; super-manus only owns the state layer.

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

## Quickstart

```
/super-manus:start my-feature   # creates docs/super-manus/<date>-my-feature/
                                # with prd.md / task_plan.md / findings.md / progress.md
/super-manus:brainstorm         # 5-question PRD Q&A → fills prd.md, distills task_plan.md ## Goal,
                                # suggests Phases (you review)
... work, edit files, take notes in findings.md ...
/super-manus:phase 1            # seed an impl plan for phase 1: tasks/p1_impl.md
git commit -m "..."             # post-commit hook prompts agent to log the commit
/clear                          # safe — state is on disk
... next session ...            # SessionStart hook restores task_plan.md automatically
```

Other commands: `/super-manus:switch <feature>` to swap active feature, `/super-manus:catchup` to re-inject the plan mid-session, `/super-manus:log` to write a session-log entry on demand.

**Three-layer separation** (no overlap):

- `prd.md` is **WHAT** — product spec only (Problem / Demo / Must / Nice / Not). Capped at ~500 words. No DB schema, no API design.
- `task_plan.md` is **HOW-overview** — `## Goal` is one sentence + pointer to `prd.md`; `## Phases` table tracks status across the whole feature.
- `tasks/p<n>_impl.md` is **HOW-detail** — DB schema, API endpoints, interface contracts, code, all per phase.

Phase status, commit log, and session summaries accrue to the feature folder; you read them, the agent reads them, and `/clear` no longer costs you context.

**Session log cadence**: the Stop hook fires at the end of every agent reply, so super-manus rate-limits when it surfaces the question to the agent. Two signals, OR'd by default:

- `SUPER_MANUS_LOG_EVERY_N_TURNS` — surface every N turns (default `5`)
- New commits since the latest `### Session …` entry — surface as soon as the post-commit hook records activity that the session log hasn't covered yet

When either signal fires, the agent is asked to **judge** whether the activity is worth a new line. If the last few turns produced nothing log-worthy, the agent just stops; otherwise it prepends one entry to `## Session log`. So the cadence is "rate-limited prompt + LLM decision" rather than a forced write every time.

Choose the policy via `SUPER_MANUS_LOG_MODE`:

- `both` (default) — whichever signal fires first
- `turns` — turn count only
- `commit` — only on unlogged commits (best if you commit at meaningful checkpoints)
- `off` — disable auto-fire entirely; use `/super-manus:log` for explicit triggers

`/super-manus:log` writes one immediately (no judgment, you said so) and resets the turn counter. The post-commit hook is independent — every Bash-tool `git commit` still produces a `## Completed commits` line.

## What it does NOT do

v0.1 is deliberately small. The following are out of scope (deferred to v0.2+ or owned by other tools):

- TDD task executor — `tasks/p<n>_impl.md` persists per-phase planning detail in v0.1; an executor that runs against it is v0.2 work
- Subagent dispatch
- Code review integration
- Git worktree integration
- Multi-harness support (Codex / Cursor / Gemini) — Claude Code only for v0.1
- TDD enforcement
- Automated test running (use your existing toolchain)
- PR creation or merge integration
- Multi-language commit message parsing — the post-commit hook reads the hash and message verbatim
- Conflict resolution between concurrent writers — single-threaded by Claude Code's tool execution model

## Coexistence with superpowers

super-manus and superpowers can both be installed; they don't fight:

- super-manus owns SessionStart / Stop / PostToolUse hooks for the **state layer**.
- superpowers owns its own SessionStart hook for skill bootstrap — both fire, both inject, no conflict.
- super-manus skills don't auto-trigger; `using-sm` is invoked only when you run `/super-manus:*`.
- Plans written by superpowers' `writing-plans` (`docs/plans/*.md`) are independent of super-manus' feature folders. Use `writing-plans` for TDD execution plans and super-manus for cross-session feature state.

## Layout

The on-disk layout super-manus creates inside a project that uses it:

```
<project-root>/
├── .super-manus/
│   └── active                                  # text file: current feature folder name
└── docs/super-manus/
    └── <YYYY-MM-DD>-<feature-name>/
        ├── prd.md                              # product spec — WHAT (≤500 words; /super-manus:brainstorm)
        ├── task_plan.md                        # phase index — HOW-overview (Goal pointer + Phases table)
        ├── findings.md                         # research / decisions / errors (LLM-maintained)
        ├── progress.md                         # commit log + session summaries (LLM-written, structured)
        └── tasks/
            └── p<n>_impl.md                    # per-phase technical plan — DB / API / code (lazy, /super-manus:phase <n>)
```

## Status

v0.1, persistence only. v0.2 may add a TDD executor that runs against `tasks/p<n>_impl.md`.
