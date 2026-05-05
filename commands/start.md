---
description: Create a new super-manus v0.2 feature folder and set it active
---

The user wants to start a new super-manus feature. Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sm-start.sh" "$ARGUMENTS"
```

If the script exits non-zero, surface its stderr to the user verbatim and stop.

If it exits zero, the script printed the absolute path of the created folder. Tell the user:

> Started feature `<name>` at `<path>`. v0.2 skeleton seeded:
> - `prd/_index.md` — feature-level overview, module manifest, data flow
> - `prd/` — per-module PRDs land here after `/super-manus:brainstorm`
> - `impl/` — per-module per-milestone update folders go here
> - `roadmap.md` — module status table (auto-managed)
> - `prd_drift.md` — PRD ↔ implementation conflict log (append-only)
>
> Next: run `/super-manus:brainstorm` to define the product spec and split into modules.

Then load the new prd/_index.md by reading `<path>/prd/_index.md` so you have it in context for the rest of the session.
