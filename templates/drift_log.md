<!-- drift_log.md (v0.9.5 R10 — renamed from prd_drift.md; v0.9.7 R15 — Author
column added between Date and Module): append-only log of PRD ↔ implementation
conflicts AND spec ↔ implementation conflicts. Two H2 sections (## PRD drift /
## Spec drift) keep the two drift kinds separate but share a stable 5-column
schema: | Date | Author | Module | Conflict | Resolution |.

The Author cell is sourced from `git config user.name` at append time (falls
back to `unknown` if unset). It identifies WHO appended the row — Resolution-
cell flips (pending → absorbed) are visible in `git log -p` for anyone who
needs that audit step.

Rows are append-only; only the Resolution cell is mutable. Rows themselves are
never deleted or reordered. Resolution is filled in by /super-manus:prd-update
or /super-manus:spec-update (or by the user manually editing to `reverted`
plus a paired findings.md note when the implementation was rolled back).
The agent must NOT silently update PRD or spec — drift is always logged here
first and resolved by the user.

Headings are stable — hooks, scripts, agents, and tests parse them by exact
match. -->
# Drift log

## PRD drift

| Date | Author | Module | Conflict | Resolution |
| --- | --- | --- | --- | --- |

## Spec drift

| Date | Author | Module | Conflict | Resolution |
| --- | --- | --- | --- | --- |
