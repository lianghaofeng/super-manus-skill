# super-manus smoke procedure

This is the manual end-to-end check for super-manus. Run through it after installing the plugin (or after a major refactor) to confirm the catchup flow works against a real Claude Code session.

## Prerequisites

- Claude Code installed
- super-manus repo at `~/code/super-manus` (or anywhere on disk)
- A scratch project directory (NOT the super-manus repo itself) — e.g. `mktemp -d`

## Install

Symlink (or git-clone) super-manus into Claude Code's plugin directory:

```bash
ln -s "$(pwd)" ~/.claude/plugins/super-manus
# Or for a real install:
# git clone <repo-url> ~/.claude/plugins/super-manus
```

Restart Claude Code (or run `/plugin reload` if available) so the plugin manifest is picked up.

## Smoke checklist

Run each step in a fresh Claude Code session in the scratch project directory.

### 1. /sm start creates a feature folder

In Claude Code:
```
/sm start smoketest
```

Expected:
- Claude reports the feature was created
- `docs/super-manus/<TODAY>-smoketest/` exists with three files: `task_plan.md`, `findings.md`, `progress.md`
- `.super-manus/active` contains `<TODAY>-smoketest`
- All three files have `<feature title>` substituted to `smoketest`

### 2. SessionStart hook injects the plan after /clear

In Claude Code:
```
/clear
```

Then in the next message, ask:
```
What feature are we currently on? What phase?
```

Expected: Claude refers to `smoketest` and references the Phases table from `task_plan.md` WITHOUT being told. (The injection happened via the SessionStart hook reading `.super-manus/active`.)

### 3. /sm catchup re-injects the plan mid-session

If you've drifted away from the plan, run:
```
/sm catchup
```

Expected: Claude re-loads the plan into context.

### 4. Manual progress.md update via post-commit hook (Phase 7+)

After Phase 7 lands: make a `git commit -m "feat: smoketest commit"` from a Bash tool call within a Claude Code session. Expected: Claude sees a system reminder telling it to update `progress.md ## Completed commits`, and does so before proceeding.

Note: the post-commit hook only triggers on the literal command prefix `git commit ...`. Aliases like `git ci` are not detected. Use full `git commit` from Claude Code's Bash tool calls.

### 5. Session log via Stop hook (Phase 8+)

After Phase 8 lands: end the Claude Code session. Expected: Claude writes a session log entry to `progress.md ## Session log` before stopping.

### 6. Catchup across sessions

Open a fresh Claude Code session in the same scratch project the next day. Expected: Claude immediately knows which feature is active, which phase is in progress, and what the most recent commits closed — all from the SessionStart injection.

## Pass / fail

Pass if steps 1, 2, 3 work today (Phase 6 ships). Defer 4, 5, 6 to after Phases 7, 8, 10.

If any step fails, file a task in this very repo's `task_plan.md` (yes, dogfood — you should `/sm start super-manus-bugs` and log it there).
