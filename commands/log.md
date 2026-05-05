---
description: Manually append a session log entry to progress.md for the active super-manus feature now
---

The user wants to update the session log immediately, without waiting for the every-N-turns auto-trigger.

Resolve the active feature folder by reading `.super-manus/active`; the folder is `docs/super-manus/<that-name>/`.

Re-read `<folder>/progress.md ## Completed commits` (the source of truth — your memory may be stale), then prepend one entry to `## Session log`:

```
### Session <YYYY-MM-DD> #<N> (<HH:MM>–<HH:MM>)
- <closed phases / key commits this session>
- <blockers, if any>
- Next session should first: <one concrete action>
```

If any phase is now blocked, flip its row in `<folder>/task_plan.md` Phases table to `blocked` with a one-line reason.

Then reset the turn counter so the next auto-trigger starts fresh:

```bash
folder="docs/super-manus/$(cat .super-manus/active)"
sid=$(awk '{print $1}' "$folder/.session-state" 2>/dev/null || echo unknown)
echo "$sid 0" > "$folder/.session-state"
```

If `.super-manus/active` is missing, tell the user there's no active feature and suggest `/super-manus:start` or `/super-manus:switch`.
