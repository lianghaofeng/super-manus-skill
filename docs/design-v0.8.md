# super-manus — Design Doc (v0.8)

> Current design. Adds a passive **runtime probe** stage to `/super-manus:reverse-prd` so the architect can cross-validate static source reading against what's actually running, plus a smarter tool-budget formula that scales with module count.
>
> Supersedes [docs/design-v0.7.md](design-v0.7.md) (v0.7 — 4-agent reviewer pipeline). The reviewer pipeline, Reflexion-style cross-phase memory (v0.7.4), the dual-layer ESCALATE_TO_USER voice (v0.7.5), all skills, hooks, layout, and the rest of the slash command surface are unchanged from v0.7.

## 1. What changed from v0.7

A user reported `/super-manus:reverse-prd` accuracy drift on a project with multiple revisions over time. Symptoms:

- The PRD `## Modules` table listed long-defunct directories (`apps/old-prototype/` still on disk, no entry in compose, never launched in months) as live modules — pure static reading sees the directory and treats it as in-scope.
- Edges in `## Data flow overview` connected modules whose runtime URLs no longer matched anything listening on the declared port.
- `## What users get` capability lists for some modules missed routes that were in fact registered dynamically at runtime, and conversely listed routes that source declared but were disabled at runtime by feature flags.

Root cause: every signal v0.7's `reverse-prd-architect` consumes (compose declarations, source files, env vars, LSP symbols, grep matches) is a **declaration of intent**. None of them tells you whether the project still launches the thing. On long-lived codebases with revisions, declarations outlive runtime — and the static analysis treats dead code as live.

v0.8 closes the gap with a **runtime probe** stage that runs between Stage 1 module discovery and the architect's content-writing pass. The probe is read-only (no business-side traffic, no schema mutations); the only mutating action is `docker compose up -d`, gated through `AskUserQuestion` so the user explicitly opts in.

```
/super-manus:reverse-prd

  Setup + mode resolution + confirmation gate     ← v0.7.2 (unchanged)
            ↓
  Stage 1 — Module discovery (declarative)        ← v0.7.0 (unchanged)
            ↓
[NEW]  Stage 2 — Runtime probe                    ← v0.8.0
        ├─ Bash: scripts/probe-runtime.sh
        │       → ps + lsof + docker ps + curl /openapi.json + git activity
        │       → fixed-format text into runtime_facts
        │
        ├─ if compose-defined services are stopped:
        │     AskUserQuestion → "Start with docker compose up -d?"
        │      ├─ Start  → run docker compose up -d, poll up to 60s,
        │      │           re-run probe, replace runtime_facts
        │      └─ Skip   → keep static-only runtime_facts
        │
        └─ runtime_facts → architect spawning prompt
            ↓
  Spawn reverse-prd-architect with runtime_facts  ← v0.8.0 (architect honors
            ↓                                       Cross-validation protocol)
  Verify post-conditions + roadmap update         ← v0.7.0 (unchanged)
```

The architect treats `runtime_facts` as a second source alongside static reading and emits structured `(audit)` subtypes when the two disagree.

## 2. Stage 2 — Runtime probe

### 2.1 The probe script (`scripts/probe-runtime.sh`)

A single bash script with a strict read-only contract. Always exits 0; total wall-clock budget ≤ 30s; every external call has a per-command timeout. Output is plain text with fixed `=== ` / `--- ` headers — orchestrator and agent both depend on these as the API.

| Section | Source | Why |
|---|---|---|
| `--- Running processes ---` | `ps -eo pid,command` filtered by language patterns + project-root substring | Highest signal for "what's actually live"; differentiates modules with running entries from defunct directories |
| `--- Listening ports ---` | `lsof -iTCP -sTCP:LISTEN -P -n` (darwin) or `ss -tlnp` (linux) | Validates module-level URL claims; feeds the OpenAPI candidate-port set |
| `--- Docker containers ---` | `docker ps --format '{{.Names}}\t{{.Image}}\t...'` | Confirms compose-launched modules; container name maps to module via convention `<project>-<service>-1` |
| `--- Compose services ---` | `docker compose -f <file> ps --format ...` | The orchestrator's signal for the docker-startup gate (zero `running` rows + non-empty compose file = ask user) |
| `--- OpenAPI contracts ---` | `curl --max-time 3 localhost:<port>{/openapi.json,/docs/openapi.json,/swagger.json,...}` | One curl can replace 20 `Read` calls across route files; ground-truth for the architect's `## What users get` cross-check |
| `--- Git activity ---` | `git log --diff-filter=D` (deleted in last 50 commits), cold files (no edit in 6 months), hot files (most-edited) | Dead-code suspicion: a module entry file in "Cold files" with no running process is a strong move-to-`Out of scope` signal |
| `--- Notes ---` | Platform / total duration / list of skipped probes with reasons | Lets the architect distinguish "probe ran, found nothing" from "probe was skipped" — only the former triggers `(audit — runtime-unverified)` |

Two design decisions worth calling out:

1. **OpenAPI port set is bounded.** A naive "curl every listening port" loop blows the budget on a developer machine (30+ ports between WeChat, Code, system services). The script intersects compose-declared ports + `--ports` arg with actually-listening ports, filters out known-infra ports (postgres, redis, kafka, etc.), caps at 10 candidates, and tries 7 OpenAPI paths each. Worst case ≈ 70 curls × 3s = 210s but with early-exit-on-first-200 the realistic case is < 10s.
2. **`with_timeout` falls back to perl alarm.** macOS lacks GNU `timeout` by default. The script tries `timeout` → `gtimeout` → `perl -e 'alarm shift; exec @ARGV'`. Perl alarm is silent (no job-control "Killed: 9" noise to stderr) and ships with macOS by default.

### 2.2 The Docker startup gate (orchestrator side)

If the probe shows `Compose services` listing a compose file but zero services running AND `Docker containers` is empty, the orchestrator asks via `AskUserQuestion`:

> Found `<compose file>` but no services are running. Reverse-prd is more accurate when services are live. Start them with `docker compose up -d` now?
>
> - Start services (~30–60s wait)
> - Skip dynamic probing

On "Start": orchestrator runs `docker compose -f <file> up -d` and polls `docker compose ps` every ~5s up to 60s waiting for all services to reach `running`/`healthy`. Success → re-run probe and replace `runtime_facts`. Timeout → keep partial probe, append `(audit — startup timeout)` note.

On "Skip" (or no compose file detected at all): proceed with the static-only `runtime_facts`. The architect honors the Cross-validation protocol's "if probe was skipped, no runtime markers" rule, so the PRD doesn't get sprinkled with false-positive `(audit — runtime-unverified)` lines.

This is the only mutating action in the v0.8 stack and it's user-gated. The probe script itself has zero side effects.

### 2.3 Cross-validation protocol (agent side)

The architect's prompt gains a `## Cross-validation with runtime_facts` section. Five rules:

1. **Module liveness** — listed module with no matching process / container / listening port → `(audit — runtime-unverified)` on its `## Modules` row.
2. **Dead-code suspicion** — module's primary entry file appears in `Cold files` AND no running process → one-line `## Open questions` entry suggesting move to `Out of scope`.
3. **Capability cross-check via OpenAPI** —
   - 3a Match (route in both static + OpenAPI): no marker, high confidence.
   - 3b Static-only (route declared in source but missing from OpenAPI): `(audit — source-runtime-conflict)`.
   - 3c Runtime-only (route in OpenAPI but no static evidence): add to `## What users get` with `(audit — runtime-only)`.
4. **Edge confidence** — both endpoints running + URL-port match → high confidence; otherwise stays at static confidence (do NOT flood every edge with audit markers).
5. **Probe-skipped guard** — if `runtime_facts` is empty / every section is `(none)` / `(probe unavailable)`, skip the entire protocol; bare `(audit)` policy remains.

Three new `(audit)` subtypes layer on top of the existing bare `(audit)` and freeform `(audit — <reason>)`:

| Subtype | When | Example |
|---|---|---|
| `(audit — runtime-unverified)` | Static evidence exists, runtime probe couldn't confirm | `\| parent-api \| [...] \| Order placement (audit — runtime-unverified) \|` |
| `(audit — runtime-only)` | Runtime evidence exists, static source not located | `- POST /api/refund — exposed at runtime (audit — runtime-only)` |
| `(audit — source-runtime-conflict)` | Static and runtime disagree | `- GET /api/legacy-export — declared in router.py (audit — source-runtime-conflict: not exposed at runtime)` |

## 3. Smart tool budget

v0.7's reverse-prd-architect carried a flat `≤10 LSP + ≤30 grep / Read` cap from the v0.4 era. That cap predates monorepo support: a single-module project gets 40 calls (excessive), a 12-module project also gets 40 (insufficient — the architect runs out of budget halfway through writing module files and starts emitting `(audit)`-stuffed sections out of frustration).

v0.8 replaces the flat cap with a per-module formula:

```
budget = 10 + 5 × N + 10  (cap 60)
```

| N modules | Budget |
|---|---|
| 1 | 25 |
| 3 | 35 |
| 6 | 50 |
| 8 | 60 (cap) |
| 12 | 60 (cap) |

Three terms:
- **`+10` base pool** — `_index.md` work that doesn't scale with module count (Problem / Audience / Demo / overall diagram synthesis).
- **`+5 × N` module increment** — per-module reading (entry file, routes, env vars, LSP find-references).
- **`+10` probe pool** — the architect doesn't spend calls running the probe itself (orchestrator does that), but it does spend calls re-reading specific source files to corroborate runtime findings (e.g. "OpenAPI says POST /api/refund exists, where in the code is it registered?").

The cap of 60 prevents pathological cases where N is huge (15+ modules); at that scale the architect should strategically deepen on the most-trafficked subset and mark the rest `(audit)`.

The budget remains honor-system — the architect tracks calls in its own scratch space, same as v0.7. The change is in the prompt's spend-priority guidance: `runtime_facts` reads are **free** (already in the prompt), and the architect is told to consume that section before opening any source file.

## 4. Per-agent model + effort routing

Pre-v0.8 every subagent inherited its model from the parent thread — running on Opus 4.7 meant every spawn used Opus 4.7 at default reasoning depth. v0.8 pins each agent's model and effort explicitly via frontmatter (with a refinement in v0.8.2 — see below), so the routing is consistent regardless of which model the user has selected for their main thread, and the heaviest reasoning is concentrated where it matters most.

| Agent | model | effort | Why |
|---|---|---|---|
| `reverse-prd-architect` | opus | max | Whole-project PRD synthesis + ASCII diagram + cross-validation in one pass — heaviest single-shot agent in the plugin |
| `impl-architect` | opus | max | Phase planning is where the v0.7 reviewer pipeline was added to catch fabrication; reasoning quality here determines whether the next two writers are doing useful work |
| `impl-reviewer` | opus | max | Exists specifically to catch what the writers can't catch about themselves; cannot afford reasoning shortcuts |
| `impl-test-writer` | **inherit** | high | Constrained by the architect's plan; writing tests is structured translation. v0.8.2 — let main-thread model flow through (Sonnet main → sonnet writer for free; Opus main → opus writer) |
| `impl-code-writer` | **inherit** | high | TDD-bound (red → green = success); model + tests provide a clear correctness signal. v0.8.2 — same rationale |
| `sync-planner` | **inherit** | high | Output is one 3–6 row Phases table; narrow scope, short output. v0.8.2 — same rationale |

**Why thinkers stay pinned to opus**: planning + review failures cascade. A bad plan wastes a test-writer + code-writer cycle; a missed reviewer call ships broken code. These three agents are the v0.7 review pipeline's reason for existing. We refuse to silently downgrade them when a user happens to be on a cheaper main thread — they explicitly must override via `.super-manus/agents.yml` (v0.8.1) if they want sonnet for these.

**Why writers use `inherit`**: writing tests + writing code under TDD discipline are constrained roles. Sonnet 4.6 handles them well, and the alternative (hard-pin opus) silently overcharges Sonnet-main users. The `inherit` value is documented in Claude Code's subagent model resolution order — when the frontmatter is `inherit`, the runtime falls through to (1) `CLAUDE_CODE_SUBAGENT_MODEL` env var, (2) the parent session's model. So users have two native override knobs for writers without touching plugin files.

**Effort priority** (high → low, per Claude Code docs):

1. `CLAUDE_CODE_EFFORT_LEVEL` env var — wins over everything below
2. Per-spawn parameter (Agent tool — super-manus does not use this)
3. Frontmatter `effort:` (the plugin's `max` for thinkers / `high` for writers)
4. Model default

The frontmatter `effort:` values are **defaults**, not floors. A user who exports `CLAUDE_CODE_EFFORT_LEVEL=medium` globally caps super-manus to medium effort across all six agents. That's the user's call — the plugin documents the default but doesn't fight the env var.

**Model priority** (high → low):

1. Per-spawn `model:` parameter to Agent tool — super-manus uses this when `.super-manus/agents.yml` declares an override (v0.8.2)
2. CLI `--agents '<json>'` inline definitions — orthogonal to plugin config
3. Frontmatter `model:` field
4. `CLAUDE_CODE_SUBAGENT_MODEL` env var — applies ONLY to subagents whose frontmatter says `model: inherit` (v0.8.2 makes 3 writers eligible for this)
5. Parent session's model — fallback for `inherit` agents when env var is absent

**Override paths summarized**:

| Want to do | Path |
|---|---|
| Switch one agent's model in this project | `.super-manus/agents.yml` (v0.8.1 — written once, committed) |
| Switch all writer-tier subagent models for one shell | `export CLAUDE_CODE_SUBAGENT_MODEL=...` (v0.8.2 — works because writers are `inherit`) |
| Cap effort across all subagents globally | `export CLAUDE_CODE_EFFORT_LEVEL=...` |
| Replace one agent for one project | Drop `agents/<name>.md` at `.claude/agents/<name>.md` (project scope > plugin scope; full frontmatter override including `effort:`) |
| Override at CLI launch | `claude --agents '{"<name>": {...}}'` (highest precedence; rare) |

## 5. Files touched

| File | Type | Lines |
|---|---|---|
| `scripts/probe-runtime.sh` | New | ~250 |
| `tests/test_probe_runtime.sh` | New | ~95 |
| `agents/reverse-prd-architect.md` | Edit | +60 (new sections) + 2 (model/effort frontmatter) |
| `commands/reverse-prd.md` | Edit | +30 (Stage 2) |
| `agents/{impl-architect,impl-reviewer,impl-test-writer,impl-code-writer,sync-planner}.md` | Edit | +2 each (model/effort frontmatter) |
| `tests/test_agent_*.sh` (all 6) | Edit | +5 each (model/effort assertions + v0.8 reverse-prd assertions where relevant) |
| `tests/test_command_reverse_prd_logic.sh` | Edit | +25 (v0.8 assertions) |
| `.claude-plugin/plugin.json` + `marketplace.json` | Edit | version 0.7.5 → 0.8.0 |

Untouched: hooks, all skills, all templates, all other agents, all other commands. The change is **strictly additive on top of v0.7**.

## 6. Out of scope (v0.8)

- Postgres / MySQL `\dt` schema probing — too password / schema / config dependent; signal density too uneven. May land in v0.8.x if a user reports it's missing.
- Active health-check probing (`/health`, `/ready`) — borderline read-only but introduces side effects on rate-limited endpoints; v1 stays purely passive.
- Host-native process autostart — only `docker compose up -d` is gated. Users with native `npm run dev` / `uvicorn` setups must start them manually before reverse-prd.
- Trace / metrics scraping — out of scope for "PRD inference"; live observability data answers different questions.
- Cross-update probe cache — every reverse-prd invocation re-runs the probe; the 30s budget makes caching unnecessary.
- A separate `/super-manus:reverse-prd-recheck <module>` command for the "user starts services post-hoc, wants me to redo cross-validation" flow — current confirmation gate (v0.7.2) already protects audited PRDs, and re-running per-module mode is an acceptable workaround.

## 7. Migration

None. v0.7-era PRD bundles continue to work — the architect's Cross-validation protocol explicitly handles the "no runtime_facts" case (rule 5: skip the protocol entirely). The new `(audit — <subtype>)` markers are additive on top of bare `(audit)`; existing tooling that grep's `\(audit\)` continues to match.

`.claude-plugin/plugin.json` bumps `0.7.5 → 0.8.0`.

## 8. v0.8.1 — `.super-manus/agents.yml` model override

Pinning model + effort in plugin frontmatter (v0.8.0) is the right default but doesn't let a user say "I want reverse-prd-architect on sonnet for cost reasons on this side project." v0.8.1 adds a thin override layer — only for `model:`, intentionally not for `effort:`.

### Storage

`<project_root>/.super-manus/agents.yml` — committed, intended for static user preferences. The `.super-manus/` directory was last used in v0.3 as the home of the `.super-manus/active` dynamic-state file; v0.4 removed that file and proved that active-update resolution belongs to mtime scans of `docs/super-manus/impl/<module>/*/`. v0.8.1 reinstates `.super-manus/` for STATIC config only, with a hard invariant: no dynamic state may live there. The two directories carry intentionally different roles:

| Path | Role | Reviewed in PR? | Mutated by hooks? |
|---|---|---|---|
| `docs/super-manus/` | Business state (PRD, roadmap, impl history) | Yes, every diff | Yes (Stop hook appends to progress.md, etc.) |
| `.super-manus/` | Tool config (agents.yml, future statics) | Rarely | Never |

Putting `agents.yml` under `docs/super-manus/` would clutter every PRD-review diff; `.super-manus/` stays out of the way.

### Schema

```yaml
# .super-manus/agents.yml — static user preference, edit by hand
impl-architect: opus
impl-reviewer: opus
reverse-prd-architect: sonnet     # cost-saving on PRD synthesis
impl-test-writer: opus
impl-code-writer: sonnet          # cost-saving on coding
sync-planner: opus
```

Lines are flat `<agent>: <model>` pairs. Lines starting with `#` are comments. Trailing `# comment` is stripped. Valid model values are `opus | sonnet | haiku`; anything else is silently rejected (treated as no override) so a typo doesn't propagate to the Agent tool as a malformed argument.

The seeded default has every line commented out — out-of-the-box, `/super-manus:start` doesn't change behavior, and users opt in by uncommenting.

### Resolution flow

```
                          .super-manus/agents.yml
                                  │
                                  ▼
  orchestrator command         sm_agent_model <agent>            agent file
   (impl / impl-all      ──→  (hooks/lib.sh helper, ──→  (frontmatter:
    reverse-prd / sync)        echoes model name or          model: opus,
                               empty string)                  effort: max)
                                  │
                                  ▼
                          if non-empty: pass model: <X> to Agent tool
                          if empty:     omit, agent's frontmatter applies
```

Each spawning command (`commands/{impl,impl-all,reverse-prd,sync}.md`) gains a "Per-agent model override (v0.8.1)" section instructing the orchestrator to source `hooks/lib.sh`, call `sm_agent_model <agent>`, and pass the result (if non-empty) as the Agent tool's `model:` parameter.

### What v0.8.1 does NOT add

- **`effort:` override via this file**: `.super-manus/agents.yml` routes `model:` only. Claude Code provides a separate, native env-var path for effort (`CLAUDE_CODE_EFFORT_LEVEL`) that is the highest-priority effort source — see §4 for the priority table. The plugin's frontmatter `effort:` values (`max` / `high`) are defaults, not floors. v0.8.0's docs incorrectly described frontmatter effort as unoverridable; v0.8.2 corrects that.
- **Per-update / per-phase override**: a single `.super-manus/agents.yml` applies project-wide; we don't differentiate "use sonnet for module X but opus for module Y." Splitting finer-grained is a v0.9 question if the demand shows up.
- **Auto-detection of best model per task**: human-curated only.

### Tests

- `tests/test_hooks_lib.sh` — 8 cases covering missing config, missing file, valid override, trailing comment, commented-out line, unlisted agent, invalid value (silent reject), empty agent name.
- `tests/test_command_start_logic.sh` — `sm-start.sh` seeds `.super-manus/agents.yml` from the template; seeded file has zero active overrides.
- `tests/test_template_agents_yml.sh` — template lists all 6 agents (commented), explains effort: limitation, lists valid model values.
- `tests/test_command_{impl,impl_all,reverse_prd,sync}_logic.sh` — each command markdown declares the override section + references `sm_agent_model` + `.super-manus/agents.yml`.

## 9. v0.8.2 — Writers switch to `model: inherit` + correct override docs

### Why

v0.8.0 pinned every agent to `model: opus`. That looked like the right move for "consistent quality regardless of main thread," but it had two consequences I missed in v0.8.0's design pass:

1. It blocks Claude Code's native `CLAUDE_CODE_SUBAGENT_MODEL` env var. That env var **only routes subagents whose frontmatter is `model: inherit`** — explicit `model: opus` ignores it entirely. With all six agents pinned, the env var was a no-op in our plugin, and users who'd already configured it in their shell (e.g., to default subagents to sonnet) silently saw it bypassed.
2. It silently overcharges users on Sonnet 4.6 main threads. They opted into Sonnet for a reason; getting opus on every super-manus subagent invocation is the opposite of what they expected.

Plus v0.8.0 docs incorrectly claimed `effort:` couldn't be overridden — Claude Code's `CLAUDE_CODE_EFFORT_LEVEL` env var **is** the highest-priority effort source, overriding frontmatter. That was a doc bug, not a design bug, but it would have misled users.

### Behavior change

Three writer-tier agents switch frontmatter `model: opus` → `model: inherit`:

- `agents/impl-test-writer.md`
- `agents/impl-code-writer.md`
- `agents/sync-planner.md`

The three thinker-tier agents (impl-architect / impl-reviewer / reverse-prd-architect) stay `model: opus` — they are the quality floor, and a Sonnet main thread getting sonnet-grade planning + review would silently degrade super-manus's value proposition.

For users on Opus 4.7 main threads (likely the common case), this change is **invisible** at runtime: writer agents still resolve to opus through inheritance. The change only takes effect for users on a different main model, or users who've set `CLAUDE_CODE_SUBAGENT_MODEL`.

### What v0.8.2 does NOT change

- `.super-manus/agents.yml` schema and behavior — still flat `<agent>: <model>` with `opus | sonnet | haiku`.
- `effort:` frontmatter values — still `max` / `high`.
- `sm_agent_model` helper — still `opus | sonnet | haiku` validation; users who want "use the inherit fallback" simply leave the entry commented (which falls through to frontmatter, which is now `inherit` for writers).
- The `runtime probe` work from v0.8.0 — orthogonal to model routing.

### Doc corrections in v0.8.2 (Layer A)

- §4 rewritten: full priority tables for both `model:` and `effort:`, override-path summary table.
- §8 polished: "what v0.8.1 does NOT add" no longer claims effort is unoverridable.
- `templates/agents.yml`: comment block explains effort env var path; writer examples updated to `sonnet` (since override-to-sonnet is now the realistic use case for Opus main users wanting cost savings on writers).
- `commands/{impl,impl-all,reverse-prd,sync}.md`: each "Per-agent model override" section documents the env var paths.
- `CLAUDE.md`: `## Where to look` v0.8 line updated to point at this section.

### Tests

- 3 writer-agent tests now assert `^model: inherit$` instead of `^model: opus$`.
- 3 thinker-agent tests unchanged.
- `test_template_agents_yml.sh` asserts `CLAUDE_CODE_EFFORT_LEVEL` is documented + rejects the old "effort not overridable" claim.
- `test_command_impl_logic.sh` asserts `CLAUDE_CODE_EFFORT_LEVEL` is documented as the effort override path.
