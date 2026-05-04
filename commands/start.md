---
description: Create a new super-manus feature folder and set it active
---

The user wants to start a new super-manus feature. Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sm-start.sh" "$ARGUMENTS"
```

If the script exits non-zero, surface its stderr to the user verbatim and stop.

If it exits zero, the script printed the absolute path of the created folder. Tell the user:

> Started feature `<name>` at `<path>`. Three files seeded from templates:
> - `task_plan.md` — fill in the Goal and Phases
> - `findings.md` — log decisions, errors, research as you work
> - `progress.md` — auto-managed by hooks (do not hand-edit)
>
> Run `/sm catchup` any time to re-load the plan into context.

Then load the new task_plan.md by reading `<path>/task_plan.md` so you have it in context for the rest of the session.
