---
description: Switch the active super-manus feature to an existing one
---

The user wants to switch the active super-manus feature.

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sm-switch.sh" "$ARGUMENTS"
```

If the script exits non-zero, surface its stderr to the user verbatim and stop.

If it exits zero, immediately perform the `/super-manus:catchup` flow inline: run `bash "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"` and read the resulting `hookSpecificOutput.additionalContext` to re-inject the new feature's plan into context.
