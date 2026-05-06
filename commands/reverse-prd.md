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

Stage 1 produced (a) the module list, (b) the infra_deps list, (c) the entry-point map per module. The main agent does NOT write `_index.md` or `<module>.md` itself. Instead, spawn a dedicated subagent with the **Agent tool** (`subagent_type="general-purpose"`) and the prompt below. The subagent reads sources, drafts the PRD bundle, and writes files via the Write tool. The main agent only verifies after the subagent returns.

Why a subagent: the writing pass needs a fresh context (no chat-history pollution), a focused architect/PM persona, and a sustained reading budget across many source files. Embedding it in the main thread bloats context and fragments the persona.

### Inputs to substitute into the prompt

Before spawning, the orchestrator fills in these placeholders from Stage 1 results:

- `{project_root}` — absolute path of the project being reverse-prd'd
- `{feature_folder}` — `<project_root>/docs/super-manus/<active-feature>` absolute path
- `{module_list}` — markdown table from Stage 1.5 with columns: `name | type (launch|batch) | entry_points | source_origin (apps|services|scripts|makefile)`
- `{infra_deps}` — bullet list from Stage 1.1: `<image> — used as <role hint>`
- `{monorepo_signals}` — which workspace manifests were detected (pnpm/uv/cargo/go), or "none"
- `{lsp_available}` — `true` or `false` (probe by attempting one workspace-symbol call before spawning)

### Subagent prompt (verbatim, with placeholders substituted)

```
You are a chief system architect AND a senior product manager (10 years of experience in both roles).
Your goal: produce a PRD bundle for the project at {project_root} that lets a new team member understand
the system architecture in 5 minutes. Use PM voice for business value and capabilities; switch to
architect voice for protocols / URLs / topology. Mix the two: PM lead + architect evidence.

INPUTS (provided):
- project_root: {project_root}
- feature_folder: {feature_folder}
- module_list: {module_list}
- infra_deps: {infra_deps}
- monorepo_signals: {monorepo_signals}
- lsp_available: {lsp_available}

DELIVERABLES (write directly via the Write tool, do NOT print to chat):
1. {feature_folder}/prd/_index.md — feature-level overview (≤700 words)
2. {feature_folder}/prd/<module>.md for EACH module in module_list (≤2000 words each)

================================================================================
_index.md STRUCTURE — six H2 sections, exact heading names (downstream tools parse these)
================================================================================

## Problem
One sentence, PM voice: what pain does this project solve and for whom.
Source priority: (1) project root package.json/pyproject.toml description field;
(2) first paragraph of README.md; (3) CLAUDE.md if present.
If all three are silent, write `(audit — describe the problem this codebase solves)`.

## Demo
3–5 lines, second person, concrete usage scenario. Source: README quickstart / "Getting Started"
section / docs/ top-level. (audit) only if README is empty.

## Must
Bullet list of business capabilities visible from runtime entry points (the union of
launch + batch entries from module_list). One bullet = one capability the system delivers.
NOT a re-listing of modules.

## Not doing
Bullet list of explicit non-goals. Only what README / CLAUDE.md explicitly says is out of scope.
(audit) if none.

## Modules
Table with one row per module from module_list:

| Module | File | Purpose |
| --- | --- | --- |
| <name> | [prd/<name>.md](<name>.md) | <one-line PM description copied from that module's ## Purpose first sentence> |

## Data flow overview
This section is REQUIRED to contain (in this order):
(a) An ASCII architecture diagram, see DIAGRAM RULES below.
(b) An edge list backup — one line per edge: `<A> --<protocol>--> <B> [path/topic]`.
(c) An offline-modules line: `Offline / batch modules: <comma-separated list>` listing every
    module from the Modules table that does NOT appear as a box in the diagram.
(d) 1–2 sentences in plain language explaining the architecture's core runtime loop.

================================================================================
DIAGRAM RULES (mandatory for _index.md ## Data flow overview)
================================================================================

Use box-drawing characters: ┌ ┐ └ ┘ ─ │ ▲ ▼ ◄ ► ├ ┤ ┬ ┴ ┼

Each box is one of two kinds:
- MODULE box — its label MUST exactly equal a module name from the ## Modules table.
- INFRA-DEP box — its label is the image name (postgres, qdrant, redis, prometheus, etc.).

Arrows show data flow direction. Label every edge with protocol (HTTP / WS / gRPC / SQL /
NATS subject / Redis prefix / env URL). External-actor arrows (browser / mobile / cron)
may enter the diagram but should not have boxes.

MODULE–DIAGRAM INVARIANT (HARD CONSTRAINT):
Every module-typed box label MUST match a row in the ## Modules table exactly. Conversely,
every module in the ## Modules table MUST either appear as a box in the diagram OR be
listed in the offline-modules line right after the diagram. No module is silently absent.

Diagram source: build the diagram from the compose `depends_on` graph + env-URL graph
(env vars containing sibling URLs, queue subjects, S3 bucket names) only. Do NOT infer
edges from textual reasoning or fluff.

================================================================================
<module>.md STRUCTURE — six H2 sections, exact heading names
================================================================================

## Purpose
One sentence, PM voice: business problem this module solves + role in the feature.
Source priority: (1) module's own package.json/pyproject.toml description; (2) first
paragraph of apps/<module>/README.md if present; (3) Makefile target comment above it;
(4) repo-root README mention. If none yield a sentence, `(audit — describe what this module does)`.

## Surface
Top 3–5 business capabilities this module delivers, each backed by concrete evidence
(schema / endpoint / CLI). Format each capability:

- **<capability name>** — <PM description: what users / consumers get>. Backed by:
  <concrete schema | endpoint path | CLI invocation | screen / route name>.

Source priority for evidence:
(1) PROCESS ENTRY — Dockerfile CMD/ENTRYPOINT, or the file the launch target invokes
    (e.g. `uvicorn parent_api.app:app` → `apps/parent-api/parent_api/app.py`), or the
    [project.scripts] entry. Read top-of-file imports + FastAPI/Flask/Express/Next
    route registrations directly off this file.
(2) DECLARED SCHEMA / ROUTES / CLI — for storage modules: alembic/versions/*.py or
    migrations/*.sql table definitions. For HTTP modules: every @router.<verb> / app.<verb>
    decorator + its path. For CLI modules: subcommand registry. For UI modules:
    top-level pages / route file.
(3) LSP補漏 — only if (1)+(2) don't paint a complete picture: document symbols on the
    entry file, workspace symbols filtered to the module's directory. Apply the
    Drift check protocol's double-source rule: single-source LSP claims get (audit).

Do NOT invent fields, endpoints, or screens. Use short schema sketches and bullet lists.

## Data flow
Default format: edge list (`in: …`, `out: …`, `third-party deps: …`).
If the module has ≥2 sequential steps, conditional branching, or a feedback loop, ALSO
add an ASCII sub-diagram before the edge list (use the same box-drawing characters).

Source priority:
(1) compose depends_on + sibling URL env vars (GATEWAY_URL, VERIFIER_URL, DATABASE_URL)
    + queue subject / topic names + S3 bucket names.
(2) Module entry file's outbound calls — httpx.AsyncClient(<url>) / fetch(<url>),
    nats.subscribe(<subject>) / kafka.subscribe(<topic>), SQL connection strings.
(3) LSP find-references on this module's exports (where it gets called from).
(4) grep imports for LSP misses (config-driven dispatch, dynamic loading, polyglot edges).

(audit) any single-source claim.

## Constraints
Three categories — include all that apply:

1. INFRA_DEPS CONSUMED — every infra service this module talks to with its concrete role.
   Examples: "reads/writes Postgres `<table>`", "publishes NATS subject `<X>`", "indexes
   Qdrant collection `<Y>`", "caches in Redis with prefix `<Z>`".
2. LIBRARY PACKAGES IMPORTED — every internal packages/* / libs/* this module depends on,
   resolved from this module's package.json `dependencies` / pyproject.toml
   `[project.dependencies]` filtered to internal workspace names.
3. IN-CODE CONSTRAINTS — explicit timeouts, declared rate limits, license headers,
   // TODO: PII comments, # pragma: no cover blocks indicating known-untested paths.

## Out of scope
Only what the module's README or repo-root README explicitly excludes. Do NOT speculate.
Empty section if README is silent.

## Open questions
Populate liberally: every (audit) item, every merge/split suggestion (granularity
defaults), anything you wanted to assert but couldn't verify. This is the user's audit list.

================================================================================
GRANULARITY DEFAULT
================================================================================

Per-service: one module = one runtime entry. Do NOT auto-merge in this pass (e.g. don't
fold web-parent + parent-api into "parent stack"). Suggest merges in ## Open questions instead.

================================================================================
(audit) POLICY
================================================================================

Mark a fact (audit) only if it comes from a single source and you couldn't corroborate
elsewhere. Do NOT bulk-mark whole sections — that gives the user a wall of placeholders.
Empty sections are better than (audit)-stuffed sections.

If lsp_available is false, add this line right after the H1 of _index.md:
> LSP unavailable — text-only inference; (audit) markers below are load-bearing.

But still: only mark what's actually unverified, not the whole document.

================================================================================
SOURCE READING — DRIFT CHECK PROTOCOL
================================================================================

This is from skills/using-sm/SKILL.md §4. Apply directly:
- LSP-LED where available: workspace symbols, document symbols, find-references for
  content evidence.
- DOUBLE-SOURCE / CROSS-CHECK: claim a fact only when both LSP and grep corroborate, or
  grep alone if LSP is down. Single-source surprises get (audit).
- LSP UNAVAILABLE fallback: continue with grep + Read alone, mark uncertain claims (audit),
  surface the warning at the top of _index.md.
- BUDGET: ≤10 LSP calls + ≤30 grep / Read calls total. Do NOT exhaustively read every
  source file.

================================================================================
FINAL OUTPUT TO ORCHESTRATOR
================================================================================

When all files are written, return ONE summary line:

> wrote _index.md + <N> module files; <M> (audit) markers total
```

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
