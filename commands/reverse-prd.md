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

## Hand off content generation to the architect subagent

Stage 1 produced (a) the module list, (b) the infra_deps list, (c) the entry-point map per module. The main agent does NOT write `_index.md` or `<module>.md` itself. Instead, spawn the **`reverse-prd-architect`** agent (Agent tool, `subagent_type="reverse-prd-architect"`). The architect+PM persona, ASCII diagram rules, source-priority hierarchy, `(audit)` policy, granularity default, and Drift check protocol references all live in [agents/reverse-prd-architect.md](../agents/reverse-prd-architect.md). Do NOT duplicate them here.

Why a subagent: the writing pass needs a fresh context (no chat-history pollution), a focused architect/PM persona, and a sustained reading budget across many source files. Embedding it in the main thread bloats context and fragments the persona.

### Inputs to pass in the spawning prompt

Compute these from Stage 1 results and pass them in the Agent tool's `prompt` field. The agent's definition file documents what each input means:

- `project_root` — absolute path of the project being reverse-prd'd
- `feature_folder` — `<project_root>/docs/super-manus/<active-feature>` absolute path
- `module_list` — markdown table from Stage 1.5 with columns: `name | type (launch|batch) | entry_points | source_origin (apps|services|scripts|makefile)`
- `infra_deps` — bullet list from Stage 1.1: `<image> — used as <role hint>`
- `monorepo_signals` — which workspace manifests were detected (pnpm/uv/cargo/go), or `"none"`
- `lsp_available` — `true` or `false` (probe by attempting one workspace-symbol call before spawning)

### Spawning prompt skeleton

The orchestrator's prompt to the agent should look roughly like:

> Inputs from /super-manus:reverse-prd Stage 1:
>
> - project_root: `<absolute path>`
> - feature_folder: `<absolute path>`
> - module_list: `<markdown table with one row per module>`
> - infra_deps: `<bullet list>`
> - monorepo_signals: `<value>`
> - lsp_available: `<true|false>`
>
> Produce the full PRD bundle per your agent definition. Return the summary line when done.


### After the subagent returns

The main agent (orchestrator) MUST:

1. Verify `{feature_folder}/prd/_index.md` exists and is non-empty.
2. Verify the count of `{feature_folder}/prd/*.md` files (excluding `_index.md`) equals the module count from Stage 1.5 — this enforces the **module–file 1:1 invariant** at the orchestrator level too.
3. Read `_index.md` and grep its `## Modules` table — every row's module name MUST match a `<name>.md` file in `prd/`. Mismatch → surface a one-line warning to the user (do NOT silently fix).
4. Surface the subagent's summary line verbatim to the user.

## Update `roadmap.md`

For each inferred module, add a row under `## Modules` in `<feature>/roadmap.md` with status `not-started` (the user will run `/super-manus:sync <module>` to actually start a milestone). Drop any leftover `<module-a>` placeholder if present.

## Do NOT seed any update folder

Unlike `/super-manus:brainstorm`, this command does NOT call `sm-update.sh`. The user must audit the inferred PRD first, fix `(audit)` placeholders, then run `/super-manus:sync <module>` for each module they want to begin a milestone in.

## Tell the user

In one short paragraph:

> Generated `prd/_index.md` + `<N>` per-module files for `<feature>` from a scan of the project. **This is a one-shot inference — please audit:** every `(audit)` marker is something I couldn't verify from source. After auditing, run `/super-manus:sync <module>` to start a milestone for each module you want to work on.

List the inferred modules + the count of `(audit)` placeholders per file in a short table. Stop. Do NOT begin implementation work; the user opens the audit loop.
