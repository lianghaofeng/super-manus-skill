---
description: Manually append a session log entry to the active update's progress.md now
---

The user wants to update the session log immediately, without waiting for the every-N-turns auto-trigger.

Resolve the active update folder by sourcing `${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh` and calling `sm_active_update` (no arguments — v0.4 scans `docs/super-manus/impl/<module>/*/` directly). The result is `<module>/<update-folder>`; the full target directory is `docs/super-manus/impl/<module>/<update-folder>/`.

If `sm_active_update` returns empty (no update folders exist yet), tell the user there's no active update and suggest `/super-manus:brainstorm` or `/super-manus:sync <module>`.

If `docs/super-manus/prd/` doesn't exist at all, tell the user super-manus is not enabled and suggest `/super-manus:start`.

Re-read `<target_dir>/progress.md ## Completed commits` (the source of truth — your memory may be stale), then prepend one entry to `## Session log` in this exact shape:

```
### Session <YYYY-MM-DD> #<N> (<HH:MM>–<HH:MM>)
- <what closed / what advanced — ONE line>
- <blockers, ONE line; omit the bullet if none>
- Next: <one concrete next action — ONE line>
```

**Length rules (hard)**:
- 3 bullets max. Skip the blockers bullet if there are none.
- Each bullet ≤ 1 line / ≤ 80 English chars / ≤ 30 Chinese chars. Like a standup update — not a status report.
- **No** file paths, line numbers, function names, test commands, code identifiers, or block-A/B/C decompositions. Those live in `tasks/p<n>_impl.md` and commit messages, not here.
- **No** copy-paste from the `## Completed commits` section — assume the reader will see it right above. Summarise, don't restate.
- Write plain language a teammate would use, in the user's working language (zh / en).

If any phase is now blocked, flip its row in `<target_dir>/task_plan.md` Phases table to `blocked` with a one-line reason.

Then reset the turn counter so the next auto-trigger starts fresh:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh"
update_rel=$(sm_active_update)
target_dir="docs/super-manus/impl/$update_rel"
sid=$(awk '{print $1}' "$target_dir/.session-state" 2>/dev/null || echo unknown)
echo "$sid 0" > "$target_dir/.session-state"
```
