---
description: Switch the active super-manus feature to an existing one
---

The user wants to switch the active super-manus feature.

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sm-switch.sh" "$ARGUMENTS"
```

If the script exits non-zero, surface its stderr to the user verbatim and stop.

If it exits zero, run `/sm catchup` immediately to re-inject the new feature's task_plan.md into context.
