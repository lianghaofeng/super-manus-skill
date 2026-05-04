---
description: Re-inject current super-manus feature plan into context
---

The user wants to re-load the active super-manus feature's plan into context (e.g. after a long detour).

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"
```

The hook emits a JSON object with `hookSpecificOutput.additionalContext`. Read the `additionalContext` value as the authoritative current state of the active feature, and treat it as if it had been injected at session start. Confirm to the user which feature is active and which phase is in progress.
