# super-manus v0.9.5 — deferred items log

This file is a forward-looking RFC, NOT a shipped release. Items recorded here are deferred design ideas surfaced during v0.9.4 use. Each entry stays here until either (a) it ships in a v0.9.x release (move "Status" inline) or (b) it's rejected (record rejection inline). Do NOT implement any item below without a separate user "ship it" directive.

Versioning convention: when an R-item ships, `plugin.json` bumps to `0.9.5` (or later). On ratification the "NOT yet ratified" status flips inline per R-item, same pattern as `design-v0.9.4.md`.

## Context: PRD voice discipline created a vacuum

v0.9.3 R1 pushed engineering detail OUT of PRD's `## What users get` because it broke PM voice — wire schemas, struct field names, tuning constants didn't belong in a "user manual." That cleanup was right. But pushing detail out of PRD revealed there is **no home for it inside super-manus**.

Current overflow paths, all wrong:

- **Cram into PRD `## How it connects`** — still pollutes PM voice; v0.9.3 R1 only half-fixed this.
- **Drop into `impl/<update>/findings.md ## Decisions`** — milestone time-series, wrong lifetime. A decision made in update A about table schema is invisible to update B's architect three months later.
- **Duplicate across every phase plan's `## Approach`** — phase plans are scoped to one milestone; same interface details get re-derived from source every time.
- **Live only in code** — type signatures + comments scatter; no top-level narrative; rots silently.

What's homeless:

| Content | Where it tries to live | Why that's wrong |
|---|---|---|
| Table schemas + field semantics | PRD or code comments | PRD breaks PM voice; comments scatter |
| Full request/response wire formats | PRD `## How it connects` | engineering detail in PM doc |
| Stable algorithm semantics (rate limits, ranking tie-breaks, retry policy) | scattered across findings.md + code | no module-level summary |
| Design rationale ("Qdrant not pgvector because...") | findings.md or PR description | gets buried |
| Tradeoffs ("considered X, picked Y") | nowhere | lost entirely |

v0.9.5 adds a **sibling per-module engineering reference** at `docs/super-manus/prd/<module>.spec.md` with 4 H2 sections, engineering voice, long-lived (no changelog markers, `git log` is audit). Plus slash command + reverse-prd extension to seed mechanical sections automatically.

The PRD vs spec dichotomy mirrors the established split: PRD = "what users get" (PM voice); spec = "what the system IS" (engineering voice). Same module, two perspectives, both long-lived, both target-state, both committed in PR diffs.

## R7. `<module>.spec.md` — per-module engineering reference

### Observation

PRD voice discipline (v0.9.3 R1) was correct in direction but left the displaced content without a home. Real-world dogfooding shows users either:
- Resist the PRD cleanup (engineering detail keeps leaking back into PRD),
- Or accept it but then lose the engineering content entirely.

Neither outcome is good. The fix is a structural one: provide a dedicated module-level engineering reference doc.

### Why it's not in v0.9.4

v0.9.4 focused on tightening the orchestrator + architect feedback loop (R4 commit hygiene, R5 fact injection, R6 cross-update reflections). Adding a new doc layer is a structural change deserving its own milestone.

### Proposed shape

#### File location and lifetime

```
docs/super-manus/prd/
├── _index.md                 (PM voice, project overview — unchanged)
├── <module>.md               (PM voice, per-module capabilities — unchanged)
└── <module>.spec.md          (NEW — engineering voice, per-module reference)
```

Sibling layout: same directory as PRD, both share the module name. They're two views of the same module, target-state, long-lived. No new directory.

**Required per module** (ratified). Every module declared in `roadmap.md ## Modules` MUST have a corresponding `<module>.spec.md` alongside its `<module>.md` PRD. Stateless / pure-CRUD / glue-code modules still need the file, but their sections can be `(none — module is stateless)` placeholders.

Required-mode execution:

1. **`/super-manus:start`** seeds `<module>.spec.md` (from `templates/prd_spec.md`) for every module declared at start time.
2. **`/super-manus:brainstorm`** seeds `<module>.spec.md` alongside every new `<module>.md` it creates (so newly-added modules don't get caught by the drift gate on their first milestone).
3. **`/super-manus:reverse-prd-spec`** in `scope=both` produces `<module>.spec.md` for every module on first run, even if all 4 sections start as `(none)`.
4. **End-of-update drift gate Pass 1** (R10 extension) appends a `drift_log.md ## Spec drift` row for any module that has `<module>.md` but no `<module>.spec.md`. The row is `pending`; gate blocks milestone close until resolved.

The strict requirement keeps engineering discipline uniform — every module has a stated technical contract, even if minimal. Empty-section placeholders (`(none — module is stateless)`) are explicit declarations, not omissions.

**Word cap.** Target ~3000 words of prose (soft cap; fenced code blocks and markdown tables don't count). Engineering density is higher than PRD's per-module 2000-word target.

#### 4 H2 sections (stable schema, parseable by hooks/scripts/agents)

##### `## Data contracts`

Schemas, tables, persistent field semantics, validation rules. Anything that defines "what data this module owns and how it's shaped."

Example bullets:

```markdown
## Data contracts

### `users` table

| Field | Type | Constraints | Notes |
|---|---|---|---|
| `id` | uuid | PK | generated by app, not DB |
| `email` | text | UNIQUE NOT NULL | normalized lowercase at write |
| `created_at` | timestamptz | NOT NULL | UTC, set by trigger |

### `session_token` (Redis)

Key format: `session:<uuid>`. TTL 24h sliding. Value is a JSON blob of
`{user_id, scopes[], issued_at}`. Refresh-on-read extends TTL.
```

If module has no persistent state, this section is `(none — module is stateless)`.

##### `## Interface contracts`

What this module exposes to other modules / external clients, and what it consumes. Two sub-sections (or just two bullet groups):

**Exposes** — public surface other modules call:

```markdown
### Exposes

- `POST /api/auth/signin` — body `{email, password}` → 200 `{token, user_id}` | 401 `{error: "invalid_credentials"}`.
- `validate_session(token: str) -> User | None` — Python function callable from any module; raises nothing, returns None on invalid.
```

**Consumes** — external + cross-module dependencies:

```markdown
### Consumes

- Postgres (table `users`) — primary persistence
- Redis (key `session:*`) — session cache, 24h TTL
- module `audit-log` — calls `audit_log.record_event(user_id, "signin", metadata)` on every signin attempt
```

##### `## Behavioral contracts`

Stable algorithm / SLA semantics that are user-observable AND survive implementation rewrites. Things like rate limits, retry policy, ordering guarantees, tie-break rules. NOT every algorithm — only the ones whose change would surprise a downstream consumer.

Example:

```markdown
## Behavioral contracts

- Signin rate limit: 5 failed attempts per email per 15min sliding window.
  On exceeded, return 429 with `Retry-After: <seconds>`. Counter resets
  on successful signin OR on TTL expiry, whichever comes first.
- Token refresh-on-read extends TTL only if remaining TTL < 12h. Closer
  to issue time, refresh is no-op (prevents lock contention on hot sessions).
- Concurrent signin from same email: last-write-wins on session_token;
  prior token is invalidated immediately (not at next refresh).
```

##### `## Design rationale`

Why this shape — long-lived, module-level. Distinct from `impl/<update>/findings.md ## Decisions` (milestone time-series). This section captures decisions that should outlive the milestone that introduced them.

Example:

```markdown
## Design rationale

- Sessions in Redis (not Postgres) — chosen for TTL-native expiry and
  sub-ms read latency on the signin hot path. Considered Postgres with
  a partial index on `expires_at`; rejected because expiry cleanup needed
  a separate cron and signin latency budget couldn't absorb the join.
- Token format is opaque UUID (not JWT). Considered JWT for stateless
  validation; rejected because we need server-side revocation (last-
  write-wins above) and JWT can't revoke without an allow-list anyway
  — at which point it's just a UUID with extra bytes.
```

This is the section that's 100% human-curated. Reverse-architect never touches it.

#### Write barriers

| Actor | Can write `<module>.spec.md`? |
|---|---|
| Users (manually or via `/super-manus:spec-update`) | ✓ |
| `reverse-architect` (v0.9.5 R9, formerly reverse-prd-architect) | ✓ — but section-aware (R10) |
| `impl-architect` Pass 2 | reads only, via `<spec_facts>` injection if file exists |
| `impl-test-writer` | reads only |
| `impl-code-writer` | reads only (and listed in code-writer's write barrier persona) |
| `impl-reviewer` | reads only |

The cheat-prevention pattern from v0.9.4 R4 extends: code-writer's `## Files touched` whitelist must NOT include `docs/super-manus/prd/<module>.spec.md` paths. Spec is target state; modifying it during a phase implementation would be back-channel drift.

#### Architect integration (read path)

`impl-architect` Pass 2 spawning prompt extends to include (when file exists):

- `module_spec_path` — `docs/super-manus/prd/<module>.spec.md`
- `<spec_facts>` block — verbatim contents of spec.md (or `(none — no spec for this module)`)

Architect uses `<spec_facts>` the same way it uses `<existing_code_facts>` (R5) — non-negotiable target state, every `## Approach` claim must be consistent. The two fact blocks are complementary: `<existing_code_facts>` is "what the code currently does"; `<spec_facts>` is "what the code should do per the long-lived contract." If they disagree, that IS the drift — architect surfaces it.

#### Template

`templates/prd_spec.md` (new file, parallel to existing `templates/prd_module.md`):

```markdown
<!-- prd/<module>.spec.md: this module's TARGET STATE in engineering voice.
Long-lived sibling to prd/<module>.md (which is PM voice). Both are target-
state, no changelog markers, history lives in git log + findings.md.
Target ~3000 words of prose — soft scannability cap. Fenced code blocks and
markdown tables don't count toward this. Headings are stable — hooks,
scripts, agents, and tests parse them by exact match. -->
# <module name>

## Data contracts

(none — module is stateless)

## Interface contracts

### Exposes

(no public surface yet)

### Consumes

(no dependencies yet)

## Behavioral contracts

(no behavioral contracts declared yet)

## Design rationale

(no design rationale recorded yet)
```

### Tests

- New `tests/test_template_prd_spec.sh` asserting all 4 H2 headings present + leading HTML comment carries word-cap guidance.
- `tests/test_layout_v04.sh` extended to NOT require spec.md (it's optional).
- `tests/test_agent_impl_architect.sh` asserts `module_spec_path` + `spec_facts` are documented as Pass 2 inputs.
- `tests/test_agent_impl_code_writer.sh` asserts `<module>.spec.md` is in the persona's read-only list.

### Open questions

1. **Required vs optional** — **Ratified: required per module.** See "Required per module" subsection above for execution details (start / brainstorm / reverse-prd-spec all seed; drift gate Pass 1 blocks on missing spec.md). Stateless modules satisfy the requirement with `(none — module is stateless)` placeholder content.
2. **Schema as markdown table vs fenced SQL.** `## Data contracts` example uses a markdown table; some users may prefer fenced ```sql blocks. Persona should allow both — table for cross-referencing, SQL for migration-traceable.
3. **`## Behavioral contracts` overlap with PRD `## Quality bar`** — **Ratified: upstream/downstream relationship, no de-dup.** PRD's `## Quality bar` carries the **user-facing promise** ("signin returns within 200ms p95"). Spec's `## Behavioral contracts` carries the **algorithmic semantics that deliver the promise** ("Redis sliding-window rate-limit; 429 with Retry-After on exceed; prepared statement hits idx_email"). Two views of the same thing — PRD looks out, spec looks in. They MAY discuss the same algorithm; they MUST NOT contradict. `reverse-architect` emits a **soft warning** when it detects same-topic bullets across the two ("PRD `## Quality bar` bullet '<X>' and spec `## Behavioral contracts` bullet '<Y>' appear to discuss the same behavior — please confirm upstream/downstream consistency"). The warning is informational, NOT a drift row.

## R8. `/super-manus:spec-update <module>` command

### Observation

For incremental edits to spec.md (add a new endpoint, tighten a contract, record a fresh design decision), users need a structured edit path. Mirrors `/super-manus:prd-update` for PRD.

### Why it's not in v0.9.4

R7 must land first (no spec.md to update).

### Proposed shape

Single-section minimum-edit command, same shape as `/super-manus:prd-update`:

```
/super-manus:spec-update <module>
```

Flow:

1. **Resolve target.** Module name → `docs/super-manus/prd/<module>.spec.md`. If file doesn't exist, offer to seed from template (`AskUserQuestion`: "spec.md doesn't exist for `<module>`. Create from template?").
2. **Drift check (light).** Unlike PRD's drift check (which requires LSP + grep cross-check), spec is engineering voice — it can move with the code. Surface a single soft check: "any uncommitted source changes in this module's directory?" — if yes, warn that spec edits may collide with in-flight work.
3. **Mode auto-detect** (same as `/prd-update`):
   - **Forward iteration**: user adds/tightens a bullet. No `findings.md` entry required (engineering edits don't carry product-decision weight; the spec edit itself + `git log` are the trace).
   - **Drift absorption**: a `drift_log.md ## Spec drift` row is `pending` for this module (see R10 — `drift_log.md` is the v0.9.5 R10 rename of `prd_drift.md`). Resolve by editing spec; flip Resolution to `absorbed`.
4. **Constraints during edit:**
   - One section at a time (forward iteration); multi-section requires the full reverse-prd-spec path.
   - No changelog markers (no strikethrough, no `(was: ...)`, no dated revision marks).
   - Preserve H2 structure; section names are stable.
   - Engineering voice. Schema sketches, code identifiers, file paths ALLOWED (unlike PRD).
5. **Word cap soft-check**: warn if edit pushes prose well past ~3000 words.

### Tests

- New `tests/test_command_spec_update_logic.sh` mirroring `test_command_prd_update_logic.sh`'s assertions: drift-check protocol mention, mode auto-detection, no-changelog rule, single-section discipline.

### Open questions

1. **Reuse `/prd-update` with a `--scope=spec` flag, OR new command?** — **Ratified: standalone `/spec-update` command.** `/prd-update` carries PM voice discipline + has different drift semantics (PRD drift is product-level, spec drift is technical). Reusing one command with mode flags conflates the two; separate commands keep the persona clean.

## R9. `/super-manus:reverse-prd-spec` rename + scope choice + agent rename

### Observation

Renaming surfaces the new dual-deliverable nature: the command now produces PRD AND/OR spec; the agent does both.

### Why it's not in v0.9.4

R7 must land first (no spec.md to produce).

### Proposed shape

#### Renames

| Old | New | Reason |
|---|---|---|
| `commands/reverse-prd.md` | `commands/reverse-prd-spec.md` | covers both deliverables |
| `agents/reverse-prd-architect.md` | `agents/reverse-architect.md` | `-prd` suffix misleads now that deliverables are plural |
| `tests/test_agent_reverse_prd_architect.sh` | `tests/test_agent_reverse_architect.sh` | follows agent rename |
| `tests/test_command_reverse_prd_logic.sh` | `tests/test_command_reverse_prd_spec_logic.sh` | follows command rename |
| `subagent_type="super-manus:reverse-prd-architect"` references | `super-manus:reverse-architect` | wherever spawned |

References to update: `CLAUDE.md`, `README.md`, `README.zh-CN.md`, `skills/using-sm/SKILL.md`, every other design doc, drift-gate suggestions in `commands/impl.md`, `commands/sync.md` (if it points users at reverse-prd).

**No backward-compat alias.** super-manus is 0.x; users running the old command name get "command not found" + we list the rename in v0.9.5 release notes.

#### Scope selection — interactive

Command takes the same positional `<target>` arg as before (omitted = whole-project; otherwise `<module>`). Scope is interactive on entry:

```
/super-manus:reverse-prd-spec [target]
```

First step inside the command: `AskUserQuestion`:

> What do you want to reverse-derive for `<target>`?
> - (a) Both — PRD + spec, one source-exploration pass (recommended for first run on a module)
> - (b) PRD only — `prd/<module>.md` (refresh PM-voice view; preserves existing spec)
> - (c) Spec only — `prd/<module>.spec.md` (refresh engineering-voice view; preserves existing PRD)

Default (a). Users can pass scope as a 2nd positional (`/super-manus:reverse-prd-spec api spec`) for non-interactive use, but interactive is the primary path.

#### Agent persona changes

`agents/reverse-architect.md` (renamed from reverse-prd-architect.md) gets:

- A new `## Deliverables` section explaining the two outputs (PRD + spec) and the scope choice.
- The existing PRD voice discipline (v0.9.3 R1) stays as-is for the PRD output.
- A new `## Engineering voice (for spec)` section describing the engineering-voice rules (schemas/code/paths allowed; no PM softening).
- A `## Section-aware refresh` section pointing at R10's policy table.

The 3-stage discovery (declarative module discovery → runtime probe → source/runtime cross-validation) stays unchanged — same exploration, two deliverables.

### Tests

- Renamed test files carry forward existing assertions PLUS:
  - Assert command spawns `subagent_type="super-manus:reverse-architect"` (new name).
  - Assert AskUserQuestion for scope.
  - Assert all three scope modes (`prd` / `spec` / `both`) are documented.
  - Assert agent's `## Deliverables` covers both outputs.

### Open questions

1. **Positional 2nd arg for scope (`reverse-prd-spec api spec`) vs interactive only.** Both feels right — interactive for new users, positional for repeat / scripted use. Cost: parsing logic in command; trivial. Recommendation: support both.
2. **What if user runs `scope=both` but only one file is dirty / out of date?** Rerun on the up-to-date one is wasteful but harmless (idempotent). Don't try to be clever about diff detection; the agent can detect "no changes needed" and emit `prd/spec for <module> already current; no edits made`.

## R10. reverse-architect section-aware refresh policy

### Observation

A naive "regenerate spec.md from source on every reverse run" overwrites human-curated content — especially `## Design rationale`, which is 100% human. The same lesson PRD learned with `## Open questions` (reverse-prd doesn't try to fabricate; leaves it for user).

### Why it's not in v0.9.4

R7 must land first (no spec.md sections to refresh).

### Proposed shape — refresh policy per section

| Section | Source-derivable? | Refresh behavior |
|---|---|---|
| `## Data contracts` | Yes (LSP schema files + migration history + ORM models) | **Full rewrite** on every reverse run. Mechanical. |
| `## Interface contracts → Exposes` | Yes (LSP `document-symbols` on public modules + OpenAPI spec discovery via runtime probe + grep for public function defs) | **Full rewrite**. |
| `## Interface contracts → Consumes` | Yes (grep for cross-module imports + external library calls + runtime-probed outbound connections) | **Full rewrite**. |
| `## Behavioral contracts` | Partial (grep for `time.sleep` / `retry` / `rate_limit` / `RateLimiter` decorators) | **Seed if absent.** If file already has bullets here, **preserve** them and append a final `(audit)` bullet listing newly-detected algorithm candidates the user should review. |
| `## Design rationale` | No — entirely interpretive | **Never touch.** If section is missing entirely, seed with placeholder `(no design rationale recorded yet)`. |

Same shape as existing PRD treatment of `## Open questions` — the principle is "if reverse-architect can't ground a claim in source, don't fabricate one."

### Drift surfacing

### File rename + two H2 layout (ratified)

`prd_drift.md` is renamed to **`drift_log.md`** (v0.9.5 R10). The current 4-column schema is preserved verbatim, but the file now carries two H2 sections — one per drift kind:

```markdown
# Drift log

## PRD drift

| Date | Module | Conflict | Resolution |
|---|---|---|---|
| 2026-05-11 | auth | login flow doesn't match PRD ## What users get bullet "social signin" | pending |

## Spec drift

| Date | Module | Conflict | Resolution |
|---|---|---|---|
| 2026-05-11 | auth | spec ## Behavioral contracts says "rate limit 5/15min" but src/auth/limiter.py:42 instantiates RateLimiter(10, "1m") | pending |
| 2026-05-11 | payments | missing payments.spec.md | pending |
```

H2 boundary parsing is the established super-manus idiom (used by `task_plan.md ## Phases`, `progress.md ## Completed commits` / `## Session log`, `findings.md ## Decisions / ## Errors / ## Data points / ## Reflections`). Reuses existing tooling shape.

### Behavior on contradiction

When `reverse-architect` finds source-level evidence that *contradicts* a preserved `## Behavioral contracts` bullet (e.g., spec says "rate limit 5/15min" but source shows `RateLimiter(10, "1m")`), it does NOT silently update the bullet. Instead it appends a row to `drift_log.md ## Spec drift`:

```
| <YYYY-MM-DD> | <module> | spec ## Behavioral contracts says "rate limit 5/15min" but src/auth/limiter.py:42 instantiates RateLimiter(10, "1m") | pending |
```

Similarly, **end-of-update drift gate Pass 1** writes "missing `<module>.spec.md`" rows to `## Spec drift` (R7 required-mode enforcement).

User resolves via:

- `/super-manus:spec-update <module>` — edit the bullet to match source, or absorb the drift.
- `/super-manus:prd-update` — if the deviation is actually a PRD-level NFR (e.g., signin latency promise needs updating), not a spec issue.
- Revert the source code — keep contract as authoritative.

Drift gate (BLOCKING end-of-update) counts `pending` rows across **both** H2 sections of `drift_log.md` for the module → must be zero to flip roadmap to `stable`.

### Tests

- `tests/test_agent_reverse_architect.sh` extends with:
  - Asserts `## Section-aware refresh` heading exists with the 4-row policy table verbatim.
  - Asserts "never touch `## Design rationale`" rule appears.
  - Asserts spec-drift row format documented.

### Open questions

1. **How to distinguish PRD drift from spec drift in `prd_drift.md`?** — **Ratified: rename file to `drift_log.md`, split into two H2 sections (`## PRD drift` + `## Spec drift`), preserve 4-column schema in each.** Chosen path is **E (rename) + D (two H2)** combined. Rationale: H2 boundary parsing is super-manus's established idiom (every other parsed artifact uses H2 sections); generic name (`drift_log.md`) is future-proof if more drift kinds are added later (e.g., e2e-drift); 4-column schema preserved means existing hook/script parsers only need a section-scoping change, not a schema migration.

   Migration: existing `docs/super-manus/prd_drift.md` files become `drift_log.md` with the current rows landing under `## PRD drift`. The `## Spec drift` section starts empty. R9 ship checklist includes the rename + a one-shot migration helper.

## Cross-cutting concerns

1. **R7→R8→R9→R10 dependency order.** R7 (the file structure) must land first. R8 (`/spec-update`) can land in parallel with R7 since it just edits a file. R9 (renames) can land independently but is more natural after R7 — otherwise the rename happens with no concrete spec.md to point at. R10 (section-aware refresh) requires R9 in place. **Recommended sequence: R7 → R8 → R9 → R10.**

2. **Ship together vs piecemeal?** R7 + R8 ship together (file + command). R9 alone (renames + scope question) ships separately. R10 ships separately. Three commits / three minor versions OR one v0.9.5 covering all four — user's call. The design doc style (this file) supports either.

3. **Reverse compatibility for spec.md.** Existing super-manus projects have no spec.md. v0.9.5 should not force them to create one — every spec.md is opt-in per module. The drift gate must NOT count "missing spec.md" as drift.

4. **Long-term: should `findings.md ## Decisions` be deprecated in favor of `<module>.spec.md ## Design rationale`?** Likely yes, but not in v0.9.5. The two have different lifetimes — findings.md is milestone time-series, spec is long-lived. Decisions made WITHIN a milestone (e.g., "we picked Approach B over A for this phase") stay in findings.md; decisions that outlive the milestone (e.g., "this module uses Qdrant not Postgres pgvector forever") promote to spec. Promotion is manual for now; future "decision lifter" workflow could surface "this findings.md Decision is still cited 3 updates later — promote to spec?" prompts.

## Status

**Design ratified, NOT yet implemented.** All four R-items have had their Open Questions decided (see each R-item's "Open questions" section — each OQ now carries a "Ratified:" line). Implementation still needs a separate "ship it" directive per R-item.

Ratified design decisions:

- **R7 OQ1** — Required per module (every module must have `<module>.spec.md`; stateless modules use `(none — ...)` placeholders).
- **R7 OQ3** — PRD `## Quality bar` vs spec `## Behavioral contracts` is upstream/downstream; reverse-architect emits soft warning on same-topic overlap, not drift.
- **R8 OQ1** — Standalone `/super-manus:spec-update` command (not a `/prd-update --scope=spec` flag).
- **R10 OQ1** — File rename `prd_drift.md` → `drift_log.md`, two H2 sections (`## PRD drift` + `## Spec drift`), 4-column schema preserved.

Still open:

- **R7 OQ2** (Data contracts schema format — markdown table vs fenced SQL) — defer to implementation; persona allows both.
- **R9 OQ1, R9 OQ2, R10 OQ1's migration helper** — narrowing during implementation.

Recommended sequence: R7 → R8 → R9 → R10, separate milestones, separate phase plans, separate commits.
