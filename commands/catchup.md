---
description: Re-inject project-global PRD overview + the most-recent update's task_plan into context
---

The user wants to re-load super-manus state into context (e.g. after a long detour, after `/clear`, or just to refresh).

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh"
```

The hook emits a JSON object with `hookSpecificOutput.additionalContext`. Read the `additionalContext` value as the authoritative current state of the project — it injects:

- `docs/super-manus/prd/_index.md` (project-global PRD overview + module manifest)
- the most recently modified update's `task_plan.md` (resolved purely by mtime via `sm_active_update`)
- pointers to `findings.md`, `progress.md`, `prd/<module>.md`, `roadmap.md`, `prd_drift.md`

If super-manus is not enabled in this project (no `docs/super-manus/prd/`), the hook says so — surface its message verbatim and suggest `/super-manus:start`.

If enabled but no `impl/<module>/<update>/` folder exists yet, the hook says so — suggest `/super-manus:brainstorm` or `/super-manus:sync <module>`.

Otherwise, confirm to the user which update is active (the `<module>/<update-folder>` line) and which phase is in progress.
