---
description: One-shot — scan an existing project, infer its module breakdown, and generate prd/_index.md + per-module prd/<module>.md stubs for the active feature
---

The user wants to take an existing codebase that has no super-manus PRD yet and bootstrap one. This command is **one-shot**: the agent does its best from observed source, then hands the result to the user to audit and refine. It does not run a Q&A like `/super-manus:brainstorm`.

## Setup

Resolve the active feature folder by reading `.super-manus/active`. The folder is `docs/super-manus/<that-name>/`. If `.super-manus/active` is missing or empty, tell the user there is no active feature and suggest `/super-manus:start <name>` first; then stop.

If `<feature>/prd/_index.md` already has substantive content (Problem / Demo / Must / Modules table non-empty), ask once: "PRD already exists. Replace from scratch (default), refine in place, or abort?" — default is to abort to avoid clobbering hand-tuned content.

## Scan the project

Follow the **Drift check protocol** in [skills/using-sm/SKILL.md §4](../skills/using-sm/SKILL.md). The protocol defines the LSP + grep cooperation, the double-source rule, the budget, and the LSP-unavailable fallback — this command consumes it for the bootstrap pass. Specifically:

1. **Intent layer (text, ≤10 of the grep budget)** — `package.json` / `Cargo.toml` / `pyproject.toml` / `go.mod` description fields, `README.md`, top-level `docs/`. These answer Purpose / Demo and never come from LSP.
2. **Structural layer (LSP-led)** — call **workspace symbols** to enumerate every exported symbol with its file path. Cluster the symbol list by directory; that clustering is your first guess at module boundaries.
3. **Boundary cross-check** — `ls` the project root and likely source directories (`src/`, `app/`, `packages/`, `services/`, `apps/`). Where the directory layout and the LSP symbol clustering agree, the module is firm. Where they disagree, mark the module name with `(audit)` and add an `## Open questions` line in `prd/_index.md`. Conventional folders (`db/` / `migrations/` / `prisma/` → database module; `api/` / `routes/`; `web/` / `frontend/` / `client/`; `cli/` / `bin/`; `infra/` / `deploy/`) are useful tie-breakers when the LSP signal is ambiguous.
4. **`## Surface` per module (LSP-led)** — for each inferred module, `document symbols` on its primary files (route file, migration file, CLI entry, top-level component) to read **real** function / endpoint / table names. Only LSP-confirmed names go into `## Surface`; do not rephrase or infer additional ones.
5. **`## Data flow` per module (LSP + grep)** — `find-references` on each module's exports gives the cross-module call graph. Backstop with grep for import statements / env vars / config-driven dispatch that LSP misses.
6. **`## Constraints`** — grep-only: TODOs, license headers, declared timeouts, PII comments. LSP irrelevant here.
7. **Tiny / undifferentiated project** — if neither LSP nor grep produces a coherent multi-module split, fall back to a single `core` module rather than inventing structure.

If LSP is unavailable (no language server, polyglot repo with no active server for the dominant language), apply the protocol's **LSP unavailable** fallback: continue with grep + Read alone, mark every PRD claim with `(audit)`, and add a "LSP unavailable — text-only inference; treat all `(audit)` markers as load-bearing" line at the top of `prd/_index.md`.

Budget per the protocol: LSP ≤10 workspace-symbol / find-references calls + 1 document-symbol per inferred module; grep / Read ≤30 calls. Do NOT exhaustively read every source file.

## Infer modules

Pick **2–5 modules** based on the strongest signals. Module names must be lowercase kebab-case (`^[a-z0-9][a-z0-9-]*$`). Common breakdowns:

- `db / api / frontend` (web app)
- `core / cli` (library + thin CLI)
- `ingest / processing / storage / api` (data pipeline)

Be **conservative**: only declare a module when its presence is visible in the source. Do NOT invent / guess / fabricate modules to round out the picture. If only a backend exists, the modules list is `[backend]`, not `[backend, frontend]`.

## Write the PRD

For each inferred module, write `<feature>/prd/<module>.md` from `templates/prd_module.md`, substituting `<module name>` and pre-filling each section:

- `## Purpose` — one sentence inferred from the strongest signal (manifest description, top-level docstring, README mention).
- `## Surface` — only what you can read off the source: actual tables (from migrations), endpoint paths (from route files), top-level CLI commands, top-level UI screens. Use *short* schema sketches and bullet lists. **Do not invent fields, endpoints, or screens.** When unsure, leave a one-line `(audit)` placeholder.
- `## Data flow` — what calls in, where outputs go — only from observable wiring (route handlers, service calls). Mark with `(audit)` if uncertain.
- `## Constraints` — only document the constraints visible in code: explicit timeouts, declared rate limits, license headers about compliance, `// TODO: PII` comments, etc.
- `## Out of scope` — leave empty `(audit)` unless the README explicitly says "we don't do X".
- `## Open questions` — populate liberally with anything you wanted to assert but couldn't verify from source. This is the user's audit list.

Total per module file ≤ 2000 words. If a module's `## Surface` would balloon past that, summarise — exhaustive enumeration of every endpoint / table is out of scope here; the user will refine.

For `<feature>/prd/_index.md`:

- `## Problem` — one sentence inferred from README / package description, or `(audit — describe the problem this codebase solves)` if no signal.
- `## Demo` — 3–5 lines inferred from README's quickstart or top-level docs; `(audit)` if absent.
- `## Must` — bullet list of the most prominent capabilities visible across modules.
- `## Not doing` — `(audit)` placeholder.
- `## Modules` table — one row per inferred module with the relative link `[prd/<module>.md](<module>.md)` and a one-line Purpose.
- `## Data flow overview` — short paragraph or 1–3 bullets connecting the modules. Mark `(audit)` portions.

Total `_index.md` ≤ 700 words.

## Update `roadmap.md`

For each inferred module, add a row under `## Modules` in `<feature>/roadmap.md` with status `not-started` (the user will run `/super-manus:sync <module>` to actually start a milestone). Drop any leftover `<module-a>` placeholder if present.

## Do NOT seed any update folder

Unlike `/super-manus:brainstorm`, this command does NOT call `sm-update.sh`. The user must audit the inferred PRD first, fix `(audit)` placeholders, then run `/super-manus:sync <module>` for each module they want to begin a milestone in.

## Tell the user

In one short paragraph:

> Generated `prd/_index.md` + `<N>` per-module files for `<feature>` from a scan of the project. **This is a one-shot inference — please audit:** every `(audit)` marker is something I couldn't verify from source. After auditing, run `/super-manus:sync <module>` to start a milestone for each module you want to work on.

List the inferred modules + the count of `(audit)` placeholders per file in a short table. Stop. Do NOT begin implementation work; the user opens the audit loop.
