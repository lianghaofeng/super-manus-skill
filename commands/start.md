---
description: Enable super-manus in this project (idempotent; project-global PRD layout)
---

The user wants to enable super-manus in the current project. v0.4 is project-global — there is no per-feature wrapper folder. Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/sm-start.sh"
```

The command takes no arguments. If the script exits non-zero, surface its stderr to the user verbatim and stop.

If it exits zero, the script printed the absolute path of `docs/super-manus/`. The script is idempotent — if super-manus was already enabled it just prints the path and exits 0.

Tell the user (omit the "seeded" half if `prd/_index.md` was already present):

> super-manus enabled at `<path>`. Project-global skeleton:
> - `prd/_index.md` — project-level overview, module manifest, data flow
> - `prd/<module>.md` — per-module PRDs (PM voice) land here after `/super-manus:brainstorm` or `/super-manus:reverse-prd-spec`
> - `prd/<module>.spec.md` — per-module engineering reference (sibling, target state, engineering voice — v0.9.5 R7). Seeded automatically alongside each new `<module>.md`; on re-run of `/super-manus:start` against an existing project, missing siblings get seeded too.
> - `impl/<module>/<YYYY-MM-DD>-<update>/` — per-module per-milestone update folders (created by `/super-manus:sync` and `/super-manus:brainstorm`)
> - `roadmap.md` — module status table (auto-managed)
> - `drift_log.md` — PRD ↔ implementation drift log AND spec ↔ implementation drift log, two H2 sections (`## PRD drift` / `## Spec drift`); rows append-only, only the Resolution cell is mutable (v0.9.5 R10 — renamed from `prd_drift.md`)
>
> Next: run `/super-manus:brainstorm` to define the product spec and split into modules, or `/super-manus:reverse-prd-spec` to bootstrap PRD + spec from an existing codebase.

Then load the new prd/_index.md by reading `<path>/prd/_index.md` so you have it in context for the rest of the session.
