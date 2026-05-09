---
description: Scan a codebase and generate prd/_index.md + per-module prd/<module>.md at docs/super-manus/prd/. Whole-project (no arg) or per-module refresh (with <module> arg). One-shot — does its best from source, hands result to user to audit.
---

The user wants to (a) bootstrap a fresh super-manus PRD bundle from a codebase scan (no arg, whole-project mode), or (b) refresh a single module's `prd/<module>.md` after relevant code changed (with `<module>` arg, per-module mode). This command is **one-shot**: the agent does its best from observed source, then hands the result to the user to audit and refine. It does not run a Q&A like `/super-manus:brainstorm`.

## Setup

Confirm `docs/super-manus/prd/` is a directory. If absent, tell the user super-manus is not enabled and suggest running `/super-manus:start` first; then stop.

## Mode resolution

Resolve from `$ARGUMENTS`:

- **Whole-project mode** if `$ARGUMENTS` is empty. Re-scans everything; writes `prd/_index.md` + every `prd/<module>.md`.
- **Per-module mode** if `$ARGUMENTS` matches `^[a-z0-9][a-z0-9-]*$`. Refreshes only `prd/<module>.md`; does NOT touch `_index.md`, `roadmap.md`, or any other module's PRD.

If `$ARGUMENTS` doesn't match the pattern, refuse: "Argument must be a single lowercase-kebab-case module name (e.g. `parent-api`), or empty for whole-project run."

For per-module mode, additionally validate:

- `docs/super-manus/prd/<module>.md` exists. If absent, refuse: "Module `<module>` is not in the current PRD bundle. Per-module reverse-prd only refreshes existing modules — to bootstrap a brand-new module, run `/super-manus:reverse-prd` (no arg) for a whole-project refresh, or `/super-manus:brainstorm` to author it interactively."

## Confirmation gates

Both modes use the same uncommitted/committed classification — but the file inspected differs.

**Whole-project mode**: read `docs/super-manus/prd/_index.md` and inspect `## Problem`.
**Per-module mode**: read `docs/super-manus/prd/<module>.md` and inspect `## Why this exists`.

Classify the body of that section:

- **uncommitted** — section is empty, or its body consists only of template `<placeholder>` text (e.g. `<2 sentences: the user pain + the business value...>`), or only of `(audit ...)` markers. Proceed without asking.
- **committed** — section has real human-authored content. Show a confirmation prompt via `AskUserQuestion` before proceeding:
  - **Whole-project**: `Existing audited PRD detected at prd/_index.md ## Problem. Continuing will OVERWRITE _index.md and ALL prd/<module>.md files. (Per-module audits in other modules will also be lost.) Proceed?`
  - **Per-module**: `Existing audited content detected at prd/<module>.md ## Why this exists. Continuing will OVERWRITE prd/<module>.md (other modules and _index.md untouched). Proceed?`
  - Options: `Yes, overwrite` / `No, stop`. On `No`: emit "Stopped — existing PRD preserved." and stop. On `Yes`: proceed to the next stage.

This is the v0.7.2 evolution from v0.7.0's hard-abort: previous behavior refused to overwrite committed PRDs and required the user to manually back up and clear the file. The confirmation gate keeps the safety property (no silent overwrite of audited content) while removing the friction of manual file shuffling.

## Discover modules — runtime-first (whole-project mode only)

Per-module mode skips this entire stage. The module list is the single row `<module>`; the architect spawns with `scope = single-module` and reads the existing `prd/<module>.md` only to identify what to refresh.

For whole-project mode: modules are determined by **what runs**, not by what the file tree implies. PRD modules ≈ things with a runtime identity (services that get launched, batch jobs that get triggered, CLIs that get invoked). Pure libraries with no runtime entry are dependencies, not modules.

Read the following declarative sources in order; the de-duped union is the candidate module list. This stage uses no LSP and no source-file reading — module **content** (What users get, How it connects, Quality bar) is filled in later stages.

### Stage 1.1 — Compose / orchestration manifests

Read all of: `docker-compose.yml`, `compose.yaml`, `compose.yml`, `infra/docker-compose.yml`, `deploy/docker-compose*.yml`, `k8s/*.yaml`, `kubernetes/*.yaml`, `helm/**/values.yaml`, `Procfile`, `systemd/*.service`. Skip silently if absent.

For each declared service, classify by `image:` / `build:`:

- **Infra dependency** if the image matches (case-insensitive prefix or exact): `postgres`, `mysql`, `mariadb`, `mongo`, `redis`, `memcached`, `qdrant`, `weaviate`, `chroma`, `elastic`, `opensearch`, `kafka`, `nats`, `rabbitmq`, `pulsar`, `minio`, `localstack`, `prom/`, `grafana`, `jaeger`, `tempo`, `loki`, `otel/`, `alertmanager`, `traefik`, `mailhog`, `mailpit`, plain `nginx` with no `build:`. **These do NOT become PRD modules.** Collect them in an `infra_deps[]` list — they will land in `## How it connects` of the app modules that talk to them (see Write the PRD).
- **App service** if it has a custom `build:` block, or an obviously project-specific image tag, or it doesn't match the infra list. App services are module candidates.

If no orchestration manifest exists or all services are infra deps (e.g. teachagent: pg / redis / qdrant / minio / nats / prom / grafana — apps run host-native), this stage produces no app-module candidates. **That's expected; later stages will catch them.**

### Stage 1.2 — Workspace app directories

`ls` the project root for monorepo conventions:

- `apps/*`, `services/*` — every direct subdirectory is a module candidate.
- `packages/*`, `libs/*` — only count as a module if it ALSO surfaces in another stage (compose service, Makefile launch target, scripts cluster). Otherwise it is a library; treat as a `## How it connects` mention on importers.

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
- Singletons or 2-file groups → NOT modules. They become bullets under the `## What users get` of the most-related app module (matched by filename keyword).

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

NOT used for module discovery. LSP and source-file reading are reserved for filling per-module content (What users get, How it connects, Quality bar) — see **Fill module content** below. If LSP is unavailable in this project, that affects content quality only; module discovery is unaffected.

### Budget

Stage 1 is declarative-only. ~10–20 reads total: orchestration manifests, root Makefile / package.json / pyproject.toml, per-app `package.json` / `pyproject.toml`. Do NOT read source files in this stage.

## Stage 2 — Runtime probe (whole-project + per-module modes)

This stage gathers passive runtime evidence so the architect can cross-validate the static module list against what's actually running. The probe is read-only; it never invokes mutating commands. Added in v0.8.0 to address PRD inaccuracy on long-lived projects with dead code (statically-visible modules whose entry file is no longer launched).

### Run the probe

Invoke `${CLAUDE_PLUGIN_ROOT}/scripts/probe-runtime.sh --project-root <project_root> [--ports <comma-separated ports>]` via Bash. Capture stdout into a variable `runtime_facts` (or write to a tempfile and read back — either works as long as the full text reaches the agent's spawning prompt).

The `--ports` argument is optional — pass the union of port numbers extracted from compose `ports:` declarations in Stage 1.1, comma-separated (e.g. `8000,8001,5173`). The script intersects this with actually-listening ports before probing OpenAPI contracts, so passing extra ports is harmless. If Stage 1.1 found no compose file, omit `--ports` entirely.

### Interpret + Docker startup gate

Inspect the resulting `runtime_facts` text:

1. If the `--- Compose services ---` block lists a compose file but shows zero services in `running` state, **AND** the `--- Docker containers ---` block is empty (`(none)`) — services are stopped:

   Use `AskUserQuestion`:
   - **Question**: "Found `<compose file path>` but no services are running. Reverse-prd is more accurate when services are live (it can curl `/openapi.json`, see real ports). Start them with `docker compose up -d` now?"
   - **Options**:
     - "Start services (~30–60s wait)" — orchestrator runs `docker compose -f <file> up -d`, then polls `docker compose -f <file> ps` every ~5s up to **60s** waiting for all services to reach `running` or `healthy` state. On success, **re-run probe-runtime.sh** and overwrite `runtime_facts`. On 60s timeout, keep the partial probe and append a one-line `(audit — startup timeout)` note to runtime_facts before passing it to the architect.
     - "Skip dynamic probing" — proceed with the current `runtime_facts` (which already documents services as not running).

2. Otherwise (services already running, or no compose file, or apps run host-native): proceed without prompting.

### Pass to the architect

Append `runtime_facts` to the spawning prompt as the 9th input (after `lsp_available`). The architect's `## Cross-validation with runtime_facts` protocol governs how the agent uses it.

## Hand off content generation to the architect subagent

Stage 1 produced (a) the module list, (b) the infra_deps list, (c) the entry-point map per module — for whole-project mode. For per-module mode the orchestrator skipped Stage 1 and the module list is the single row `<module>`. The main agent does NOT write `_index.md` or `<module>.md` itself. Instead, spawn the **`reverse-prd-architect`** agent (Agent tool, `subagent_type="reverse-prd-architect"`). The architect+PM persona, ASCII diagram rules, source-priority hierarchy, `(audit)` policy, granularity default, and Drift check protocol references all live in [agents/reverse-prd-architect.md](../agents/reverse-prd-architect.md). Do NOT duplicate them here.

### Per-agent model override (v0.8.1+)

Before the spawn, resolve the override model:

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh"
override=$(sm_agent_model reverse-prd-architect)
```

If `$override` is non-empty (`opus` / `sonnet` / `haiku`), pass `model: "$override"` to the Agent tool. Empty → omit and use the agent's pinned `model: opus` (thinker — quality floor for whole-project PRD synthesis). `effort:` is governed by `CLAUDE_CODE_EFFORT_LEVEL` env var (highest priority, overrides everything) → frontmatter (`max` for this agent) → model default; not configurable via `.super-manus/agents.yml`.

Why a subagent: the writing pass needs a fresh context (no chat-history pollution), a focused architect/PM persona, and a sustained reading budget across many source files. Embedding it in the main thread bloats context and fragments the persona.

### Inputs to pass in the spawning prompt

Compute these from Stage 1 results (whole-project) or directly from arguments (per-module), and pass them in the Agent tool's `prompt` field. The agent's definition file documents what each input means:

- `project_root` — absolute path of the project being reverse-prd'd
- `feature_folder` — `<project_root>/docs/super-manus/` absolute path (the project-global super-manus root in v0.4)
- `scope` — `whole-project` or `single-module` (added in v0.7.2). Selects which deliverables the agent writes.
- `target_module` — the module name when `scope=single-module`; omit when `scope=whole-project`.
- `module_list` — markdown table with columns: `name | type (launch|batch) | entry_points | source_origin (apps|services|scripts|makefile)`. For per-module mode this is one row.
- `infra_deps` — bullet list from Stage 1.1: `<image> — used as <role hint>`. Per-module mode reuses what's already declared in the existing `prd/<module>.md ## How it connects` block under Third-party / Downstream — re-derive from compose only if that section is empty.
- `monorepo_signals` — which workspace manifests were detected (pnpm/uv/cargo/go), or `"none"`
- `lsp_available` — `true` or `false` (probe by attempting one workspace-symbol call before spawning)
- `runtime_facts` (v0.8.0) — full multi-section stdout from `scripts/probe-runtime.sh` produced in Stage 2 above. Pass the entire text block; the architect's parser depends on the `=== RUNTIME PROBE ...` and `--- <section> ---` headers being intact.

### Spawning prompt skeleton

The orchestrator's prompt to the agent should look roughly like:

> Inputs from /super-manus:reverse-prd Stage 1:
>
> - project_root: `<absolute path>`
> - feature_folder: `<absolute path>`
> - scope: `<whole-project | single-module>`
> - target_module: `<module name | (omit if whole-project)>`
> - module_list: `<markdown table with one row per module>`
> - infra_deps: `<bullet list>`
> - monorepo_signals: `<value>`
> - lsp_available: `<true|false>`
> - runtime_facts: |
>     <full multi-line stdout from scripts/probe-runtime.sh — preserve headers verbatim>
>
> Produce the PRD bundle per your agent definition (per-module mode: write only `prd/<target_module>.md`, do NOT touch `_index.md` or other module files). Apply the Cross-validation with runtime_facts protocol. Return the summary line when done.


### After the subagent returns

The main agent (orchestrator) MUST:

For **whole-project mode**:

1. Verify `{feature_folder}/prd/_index.md` exists and is non-empty.
2. Verify the count of `{feature_folder}/prd/*.md` files (excluding `_index.md`) equals the module count from Stage 1.5 — this enforces the **module–file 1:1 invariant** at the orchestrator level too.
3. Read `_index.md` and grep its `## Modules` table — every row's module name MUST match a `<name>.md` file in `prd/`. Mismatch → surface a one-line warning to the user (do NOT silently fix).
4. Surface the subagent's summary line verbatim to the user.

For **per-module mode**:

1. Verify `{feature_folder}/prd/<target_module>.md` exists, is non-empty, and was modified during this run (mtime newer than spawning time). The architect must NOT have written any other file — if `Glob {feature_folder}/prd/*.md` returns more than the expected file with a fresh mtime, surface a one-line warning ("Per-module run also modified: <list>") and proceed.
2. **Cascade scan** — grep other `prd/*.md` files for case-sensitive mentions of `<target_module>` inside their `## How it connects` block. Collect the names of modules that mention the target. Also check `prd/_index.md ## Data flow overview` for any edge involving `<target_module>`.
3. Surface the subagent's summary line verbatim to the user, followed by the cascade report (see "Tell the user" below).

## Update `roadmap.md` (whole-project mode only)

For each inferred module, add a row under `## Modules` in `docs/super-manus/roadmap.md` with status `not-started` (the user will run `/super-manus:sync <module>` to actually start a milestone). Drop any leftover `<module-a>` placeholder if present.

Per-module mode does NOT touch `roadmap.md` — the row already exists.

## Do NOT seed any update folder

Unlike `/super-manus:brainstorm`'s older v0.3 behavior, this command does NOT call `sm-update.sh`. The user must audit the inferred PRD first, fix `(audit)` placeholders, then run `/super-manus:sync <module>` for each module they want to begin a milestone in.

## Tell the user

For **whole-project mode**, in one short paragraph:

> Generated `docs/super-manus/prd/_index.md` + `<N>` per-module files from a scan of the project. **This is a one-shot inference — please audit:** every `(audit)` marker is something I couldn't verify from source. After auditing, run `/super-manus:sync <module>` to start a milestone for each module you want to work on.

List the inferred modules + the count of `(audit)` placeholders per file in a short table. Stop. Do NOT begin implementation work; the user opens the audit loop.

For **per-module mode**, in one short paragraph:

> Refreshed `docs/super-manus/prd/<target_module>.md`. Other modules and `_index.md` were not touched. **Please audit `(audit)` markers** in the refreshed file.

Then, IF the cascade scan from step 2 above found other modules whose `## How it connects` block mentions `<target_module>` OR `_index.md ## Data flow overview` has edges involving `<target_module>`, add a follow-up block:

> **Cascade — these may now be stale:**
> - `prd/<other-module>.md ## How it connects` references `<target_module>` (run `/super-manus:reverse-prd <other-module>` to refresh, or edit manually).
> - `prd/_index.md ## Data flow overview` has edges involving `<target_module>` (re-running the whole-project mode would refresh the diagram, but a manual review is usually cheaper).

If the cascade scan finds nothing, omit this block and just confirm the single-file refresh.

Stop. Do NOT begin implementation work; the user opens the audit loop.
