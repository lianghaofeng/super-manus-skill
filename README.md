# super-manus

*Survives `/clear`, generates dev-readable progress journals from git history, works alongside superpowers (not a fork).*

## What

**super-manus** is a Claude Code plugin that fuses [obra/superpowers](https://github.com/obra/superpowers)' execution discipline with Manus-style ([OthmanAdi/planning-with-files](https://github.com/OthmanAdi/planning-with-files)) persistent file-based state. It owns the state layer only: a per-feature folder on disk holds your task plan, findings, and progress journal, and hooks keep them in sync as you work.

## Why

`superpowers` gives you TDD, subagent dispatch, and code-review discipline, but loses everything on `/clear` or `/compact`. `planning-with-files` gives you Manus-style persistent state across sessions, but no execution discipline.

super-manus targets the gap: persistent state that survives session boundaries, with hooks that auto-restore "where were we" without user babysitting. It does NOT re-implement superpowers' executor — v0.1 is **persistence only**. Keep using superpowers (or any other workflow) for execution; super-manus only owns the state layer.

## Install

super-manus is a static plugin distributed by `git clone` into your Claude Code plugins directory:

```bash
cd ~/.claude/plugins
git clone <repo-url> super-manus
```

Then reload plugins inside Claude Code:

```
/plugin
```

On first install, you may need to restart your Claude Code session for hooks to register.

## Quickstart

```
/sm start my-feature       # creates docs/super-manus/<date>-my-feature/
                           # with task_plan.md / findings.md / progress.md
... work, edit files, take notes in findings.md ...
git commit -m "..."        # post-commit hook prompts agent to log the commit
/clear                     # safe — state is on disk
... next session ...       # SessionStart hook restores task_plan.md automatically
```

That's the loop. Phase status, commit log, and session summaries all accrue to the feature folder; you read them, the agent reads them, and `/clear` no longer costs you context.

## What it does NOT do

v0.1 is deliberately small. The following are out of scope (deferred to v0.2+ or owned by other tools):

- TDD task executor (`tasks/` is reserved in the layout but unused in v0.1)
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
- super-manus skills don't auto-trigger; `using-sm` is invoked only when you run `/sm *`.
- Plans written by superpowers' `writing-plans` (`docs/plans/*.md`) are independent of super-manus' feature folders. Use `writing-plans` for TDD execution plans and super-manus for cross-session feature state.

## Layout

The on-disk layout super-manus creates inside a project that uses it:

```
<project-root>/
├── .super-manus/
│   └── active                                  # text file: current feature folder name
└── docs/super-manus/
    └── <YYYY-MM-DD>-<feature-name>/
        ├── task_plan.md                        # goal / phases / status (LLM-maintained)
        ├── findings.md                         # research / decisions / errors (LLM-maintained)
        ├── progress.md                         # commit log + session summaries (LLM-written, structured)
        └── tasks/                              # reserved for v0.2 executor (empty in v0.1)
```

## Status

v0.1, persistence only. v0.2 will add a TDD executor.
