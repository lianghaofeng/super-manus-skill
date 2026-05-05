---
description: Open or seed the per-phase implementation plan tasks/p<n>_impl.md for the active feature
---

The user wants to open or create a per-phase implementation plan in the active super-manus feature. Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sm-phase.sh" "$ARGUMENTS"
```

If the script exits non-zero, surface its stderr to the user verbatim and stop.

If it exits zero, the script printed the absolute path of `tasks/p<n>_impl.md`. Read that file so you have it in context, then tell the user one of:

- If the file was just seeded (Objective / Approach / Files touched / Verification are placeholders): "Seeded `tasks/p<n>_impl.md` for phase `<phase name>`. Fill in `## Objective`, `## Approach`, `## Files touched`, `## Verification` — code, pseudo-code, and file diffs go here, not in `task_plan.md`."
- If the file already had content: "Loaded existing `tasks/p<n>_impl.md` for phase `<phase name>`."

Reminder: `/sm phase` does not change phase status. When the phase actually starts or closes, edit the `## Phases` table in `task_plan.md` per the using-sm skill.
