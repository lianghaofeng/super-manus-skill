---
description: One-shot — scan an existing project, infer its module breakdown, and generate prd/_index.md + per-module prd/<module>.md stubs for the active feature
---

The user wants to take an existing codebase that has no super-manus PRD yet and bootstrap one. This command is **one-shot**: the agent does its best from observed source, then hands the result to the user to audit and refine. It does not run a Q&A like `/super-manus:brainstorm`.

## Setup

Resolve the active feature folder by reading `.super-manus/active`. The folder is `docs/super-manus/<that-name>/`. If `.super-manus/active` is missing or empty, tell the user there is no active feature and suggest `/super-manus:start <project>-bootstrap` first; then stop.

**Hard-abort if the active feature is already topic-scoped.** reverse-prd is for bootstrapping a fresh PRD from a codebase scan, not for refining a feature that already represents one subsystem. Read `<feature>/prd/_index.md` and inspect the `## Problem` section:

- Treat the feature as **uncommitted** (proceed) if Problem is empty, or its body consists only of template `<placeholder>` text (e.g. `<one sentence: what pain, for whom>`), or only of `(audit ...)` markers.
- Treat the feature as **committed** (abort) otherwise — meaning a human or a prior brainstorm has already written a real problem statement. Do NOT prompt for permission; do NOT overwrite. Emit:

  > Active feature `<name>` already has a committed PRD topic. reverse-prd dumps whole-project inferences and would overwrite that. Run `/super-manus:start <project>-bootstrap` to create a clean feature, switch to it, then re-run `/super-manus:reverse-prd`.

This guards the most common misuse: dropping a whole-project scan into a feature folder that was created for one subsystem.

## Discover modules — runtime-first

Modules are determined by **what runs**, not by what the file tree implies. PRD modules ≈ things with a runtime identity (services that get launched, batch jobs that get triggered, CLIs that get invoked). Pure libraries with no runtime entry are dependencies, not modules.

Read the following declarative sources in order; the de-duped union is the candidate module list. This stage uses no LSP and no source-file reading — module **content** (Surface, Data flow) is filled in later stages.

### Stage 1.1 — Compose / orchestration manifests

Read all of: `docker-compose.yml`, `compose.yaml`, `compose.yml`, `infra/docker-compose.yml`, `deploy/docker-compose*.yml`, `k8s/*.yaml`, `kubernetes/*.yaml`, `helm/**/values.yaml`, `Procfile`, `systemd/*.service`. Skip silently if absent.

For each declared service, classify by `image:` / `build:`:

- **Infra dependency** if the image matches (case-insensitive prefix or exact): `postgres`, `mysql`, `mariadb`, `mongo`, `redis`, `memcached`, `qdrant`, `weaviate`, `chroma`, `elastic`, `opensearch`, `kafka`, `nats`, `rabbitmq`, `pulsar`, `minio`, `localstack`, `prom/`, `grafana`, `jaeger`, `tempo`, `loki`, `otel/`, `alertmanager`, `traefik`, `mailhog`, `mailpit`, plain `nginx` with no `build:`. **These do NOT become PRD modules.** Collect them in an `infra_deps[]` list — they will land in `## Constraints` of the app modules that talk to them (see Write the PRD).
- **App service** if it has a custom `build:` block, or an obviously project-specific image tag, or it doesn't match the infra list. App services are module candidates.

If no orchestration manifest exists or all services are infra deps (e.g. teachagent: pg / redis / qdrant / minio / nats / prom / grafana — apps run host-native), this stage produces no app-module candidates. **That's expected; later stages will catch them.**

### Stage 1.2 — Workspace app directories

`ls` the project root for monorepo conventions:

- `apps/*`, `services/*` — every direct subdirectory is a module candidate.
- `packages/*`, `libs/*` — only count as a module if it ALSO surfaces in another stage (compose service, Makefile launch target, scripts cluster). Otherwise it is a library; treat as a `## Constraints` mention on importers.

Single-subdir case: if only one of these directories exists with one subdir, the project is effectively single-module — fall back to a `core` module rather than over-splitting.

### Stage 1.3 — Makefile / package scripts

Parse runnable target catalogs:

- `Makefile` — `grep -E '^[a-zA-Z][a-zA-Z0-9_.-]*:' Makefile` for top-level targets; Read each target's body (5–10 lines) to classify. **`.PHONY` is a hint about which rules exist, not a substitute for reading bodies** — many launch targets (e.g. `parent-api: uvicorn parent_api.app:app`) are indistinguishable from batch targets without reading the recipe.
- root `package.json` `scripts` field.
- `pyproject.toml` `[tool.poetry.scripts]` / `[project.scripts]` / `[tool.uv.scripts]`.
- `Justfile`, `Taskfile.yml`.

Classify each target by body content:

- **launch** — long-running process. Markers: `uvicorn`, `gunicorn`, `hypercorn`, `python -m <pkg>`, `node <entry>`, `next dev`, `vite`, `pnpm --filter <pkg> dev`, `cargo run`, `go run`, `docker compose up`, or invokes a `bin/` / `scripts/dev-up.sh` style orchestrator. → maps to a long-running module; cross-reference with 1.2 dirs to identify which one.
- **batch** — one-shot. Markers: invokes a `scripts/<name>.py` / `.sh`, `alembic upgrade`, `prisma migrate`, `python -m <pkg>.eval`, asset / model `download_*`, `bench`, `regression`, `eval`, data ETL. → candidate batch / ops module.
- **dev-workflow** — `lint`, `format`, `test`, `check`, `clean`, `install`, `help`, `ci`. → ignore; not a PRD module.

Launch targets confirm / narrow the 1.2 list. Batch targets often produce module candidates that don't appear anywhere else (for teachagent, this is where `bench-*` / `regression-*` / `db-migrate` / `download-models` come from).

### Stage 1.4 — `scripts/` verb-prefix clustering

If a top-level `scripts/` directory has ≥5 files, cluster by verb prefix or suffix:

- ≥3 files sharing a prefix (`compile_*`, `build_*`, `download_*`, `promote_*`, `audit_*`, `coach_*`, `demo_*`) or suffix (`*_eval*`, `*_lint*`, `*_smoke*`) → one batch module, named verb-noun (e.g. teachagent's `compile_canonical_taxonomy / compile_knowledge_points_md / compile_lesson_links` → `taxonomy-compilation`).
- Singletons or 2-file groups → NOT modules. They become bullets under the `## Surface` of the most-related app module (matched by filename keyword).

### Stage 1.5 — Synthesize

```
modules = (1.1 app services)
        ∪ (1.2 apps/services dirs)
        ∪ (1.3 launch + batch targets, mapped to apps where possible)
        ∪ (1.4 scripts clusters)
```

De-duplicate; canonicalize names to lowercase kebab-case (`^[a-z0-9][a-z0-9-]*$`). When two sources produce names that obviously refer to the same module (`apps/parent-api` and compose service `parent_api`), unify to one.

**No upper cap on module count.** Real monorepos can produce 8–15 modules; do not artificially trim. Only enforce a lower bound: empty union → fall back to a single `core` module.

**Be conservative**: only declare a module when its presence is visible in at least one stage. Do NOT invent modules to round out the picture. If only a backend is visible, the list is `[backend]`, not `[backend, frontend]`.

**Cross-stage disagreement** — if an `apps/<X>` directory exists with no Makefile target, no compose service, and no script reference, include it but mark its `## Modules` row with `(audit)` and add an `## Open questions` entry: "Does `<X>` still ship? No runnable entry point found in Makefile / compose / scripts."

### Stage 1.6 — LSP / source code

NOT used for module discovery. LSP and source-file reading are reserved for filling per-module content (Surface, Data flow) — see **Fill module content** below. If LSP is unavailable in this project, that affects content quality only; module discovery is unaffected.

### Budget

Stage 1 is declarative-only. ~10–20 reads total: orchestration manifests, root Makefile / package.json / pyproject.toml, per-app `package.json` / `pyproject.toml`. Do NOT read source files in this stage.

## Fill module content — LSP + grep cooperation

With the module list from Stage 1.5 in hand, the next pass reads source code to fill `## Surface` and `## Data flow` per module. This pass follows the **Drift check protocol** in [skills/using-sm/SKILL.md §4](../skills/using-sm/SKILL.md). Apply its rules directly:

- **LSP-led where available**: `workspace symbols` to enumerate exports per module, `document symbols` on each module's primary entry files (route file, migration file, CLI entry, top-level component), `find-references` on each module's exports for cross-module wiring.
- **Double-source / cross-check**: claim a fact in `## Surface` or `## Data flow` only when both LSP and grep corroborate it (or grep alone if LSP is unavailable for that file). Single-source surprises get an `(audit)` marker.
- **LSP unavailable** fallback: if no language server is active for the dominant language (polyglot repos commonly hit this), continue with grep + Read alone, mark uncertain claims with `(audit)`, and add a "LSP unavailable — text-only inference; treat all `(audit)` markers as load-bearing" line at the top of `prd/_index.md`. Module discovery (Stage 1) is unaffected — only `## Surface` / `## Data flow` quality degrades.
- **Budget**: LSP ≤10 workspace-symbol / find-references calls + 1 document-symbol per module; grep / Read ≤30 calls. Do NOT exhaustively read every source file.

## Write the PRD

For each inferred module, write `<feature>/prd/<module>.md` from `templates/prd_module.md`, substituting `<module name>` and pre-filling each section:

- `## Purpose` — one sentence inferred from the strongest signal (manifest description, top-level docstring, README mention).
- `## Surface` — only what you can read off the source: actual tables (from migrations), endpoint paths (from route files), top-level CLI commands, top-level UI screens. Use *short* schema sketches and bullet lists. **Do not invent fields, endpoints, or screens.** When unsure, leave a one-line `(audit)` placeholder.
- `## Data flow` — what calls in, where outputs go — only from observable wiring (route handlers, service calls). Mark with `(audit)` if uncertain.
- `## Constraints` — document constraints visible in code AND any `infra_deps[]` from Stage 1.1 that this module talks to (e.g. "reads from Postgres", "publishes to NATS subject `<X>`", "indexes into Qdrant collection `<Y>`"). Plus: explicit timeouts, declared rate limits, license headers about compliance, `// TODO: PII` comments. Library packages from `packages/*` / `libs/*` that this module imports also belong here.
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
