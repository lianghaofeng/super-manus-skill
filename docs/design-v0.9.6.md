# super-manus v0.9.6 — test-writer Reflexion + PRD↔spec topic-overlap radar (SHIPPED)

**Shipped in v0.9.6** (single-shot release covering R11 + R12 together). Both items
are additive on top of v0.9.5; no breaking changes, no renames, no schema migrations.

`plugin.json` bumped from `0.9.5` to `0.9.6` on this release.

## Context: gaps surfaced after v0.9.5 dogfooding

Two real-world friction points came out of v0.9.5 use:

1. **test-writer kept making the same kind of mistake across phases.** v0.9.4 R6 (Reflexion-style cross-update memory via `findings.md ## Reflections`) was implemented for `impl-architect` only. When reviewer pre-code RETURN'd test-writer for "fixture is an inline dict, not a real-file sample", that lesson was synthesized into a Heuristic and injected into the NEXT architect spawn — but never reached the next test-writer spawn. Same writer, same mistake, same RETURN.

2. **PRD and spec could silently diverge mid-edit.** v0.9.5 R7 OQ3 deliberately ratified PRD ↔ spec overlap as "upstream/downstream, not drift" — they MAY discuss the same behavior in different voices, MUST NOT contradict. The only enforcement was `reverse-architect`'s soft warning during full reverse-derivation runs. A user editing PRD `## Quality bar` ("signin returns within 200ms p95") had no way to notice that spec `## Behavioral contracts` was still claiming "no rate limiting" — the inconsistency would surface later as a phase-test failure or a customer ticket. The check should fire **at edit time**, when the user is mentally on the module.

Both gaps are addressable by reusing existing mechanisms (R6's reflection collector for #1, R7's topic-overlap detection logic for #2). No new primitives required.

## R11. PRD↔spec topic-overlap soft warning at edit time

### Observation

`/super-manus:prd-update` and `/super-manus:spec-update` are the two surgical-edit entry points; they're also the moments the user is mentally on a single module. Adding a post-edit check at these two points catches PRD/spec divergence before it propagates downstream. R7 OQ3's "no hard drift on PRD-spec overlap" still holds — the warning is **soft**, the user decides what to do, the gate is unaffected.

### Why it's not in v0.9.5

R7 OQ3 ratification originally chose to defer PRD-spec consistency enforcement entirely. After v0.9.5 dogfooding showed the silent-divergence failure mode is real, this minimal soft-warning version landed without revisiting OQ3's hard-gate stance.

### Proposed shape (shipped)

#### Trigger points

| Command | Post-edit scan target | Drift section to log to |
|---|---|---|
| `/super-manus:prd-update` (PRD edited) | `prd/<module>.spec.md` H2 sections (`## Data contracts`, `## Interface contracts`, `## Behavioral contracts`, `## Design rationale`) | `drift_log.md ## Spec drift` (resolution path: "look at spec") |
| `/super-manus:spec-update` (spec edited) | `prd/<module>.md` H2 sections (`## What users get`, `## Quality bar`, `## How it connects`) | `drift_log.md ## PRD drift` (resolution path: "look at PRD") |

The asymmetric "log to opposite section" rule reflects where the user is most likely to look next: after editing PRD, the question is "what about spec?" — so the row appears in `## Spec drift`.

#### Detection algorithm

1. **Skip if sibling missing.** PRD-update side: skip if `<module>.spec.md` doesn't exist (the missing-spec row from end-of-update gate Pass 1 already flags the gap separately). Symmetric on spec-update side.
2. **Tokenize the edited bullet.** Extract noun/verb tokens (≥4 chars, lowercase, alphanumeric, deduped) from the `new_string` just written. Skip stopwords (`that`, `this`, `with`, `from`, `into`, `when`, `then`, `what`, `your`, `will`, `have`, `been`, `would`, `should`, `could`, `also`, `only`, `both`, `each`, `more`, `most`, `very`, `just`, `like`, `such`, `some`, `many`, `much`, `even`). Aim for 5-15 candidate tokens.
3. **Scan target file's H2 sections.** Count distinct token hits per H2 section's body.
4. **Threshold:** ≥3 distinct tokens hitting a single H2 section is "potential overlap". Below 3 is noise; the threshold was chosen to dodge false positives on common nouns ("module", "user", "system") while still catching real semantic alignment.

#### User interaction (`AskUserQuestion`)

3 options:
- **(a) Open sibling to inspect** (recommended) — display the matching section, user decides
- **(b) Confirm consistent** — "PRD and spec are saying the same thing in different voices"
- **(c) Mark as soft-acknowledged** — "I'm aware of the overlap; don't open it now"

#### Logging discipline (the load-bearing R7 OQ3 honor)

| User action | Resolution column value | Enters Pass 3 hard gate? |
|---|---|---|
| (a) → user runs the other update command | `acknowledged-soft: <prd|spec>-update launched` | No |
| (a) → user decides sibling is OK as-is | `acknowledged-soft: confirmed-consistent` | No |
| (a) → user decides sibling genuinely conflicts | flip to `pending` (real drift now) | **Yes** (this is the escalation path) |
| (b) confirm consistent | `acknowledged-soft: confirmed-consistent` | No |
| (c) soft-acknowledge | `acknowledged-soft: skipped` | No |

The end-of-update gate's Pass 3 counts only `Resolution = pending` (case-insensitive) rows. `acknowledged-soft: ...` rows preserve the audit trail without blocking roadmap → stable. **This is the explicit honor of R7 OQ3** — overlap detection is informational, not enforcement, unless the user manually escalates.

Conflict column format includes the `(soft)` prefix as a parser hint:

```
(soft) PRD-spec topic-overlap: PRD edit '<one-line>' shares vocabulary with spec ## <section>
```

If overlap is NOT detected (token hit count < 3 in every sibling section), no row is written. **Silence is the default**; "no overlap detected" rows would be noise.

### Tests

- `tests/test_command_prd_update_logic.sh` extended with R11-specific assertions: section heading present, skip-if-missing-sibling rule, tokenization rule, ≥3-token threshold, AskUserQuestion with 3 options, logging-to-`## Spec drift`, `acknowledged-soft` Resolution discipline, hard-gate exemption explicit, escalation-to-pending path, silence-on-no-overlap.
- `tests/test_command_spec_update_logic.sh` extended symmetrically (logs to `## PRD drift`, scans `## What users get` + `## Quality bar`).

### Open questions (deferred)

1. **Stopword list maintenance.** Current list is a fixed inline set. Polyglot projects might want `.super-manus/stopwords.txt` overrides. Defer until at least one user reports false-positive noise.
2. **LLM-judgment fallback when keyword overlap is borderline.** Current threshold (≥3 distinct tokens) is mechanical. Could spawn a cheap haiku reviewer to judge "are these actually about the same thing?" when the count is in 2-4 range. Defer until real-world false-positive rate is measured.
3. **Should `## Soft warnings` become its own H2 in `drift_log.md`?** Currently `acknowledged-soft:` rows live in `## PRD drift` / `## Spec drift` mixed with `pending` rows. A separate H2 would visually segregate them. Defer — the Resolution column already distinguishes them and Pass 3 filters correctly; visual segregation is cosmetic.

### R11.1 patch — symmetric resolution paths after choice (a)

Initial R11 ship had `(a) Open spec to inspect` end with "user manually decides what to do, then runs `/super-manus:spec-update` separately". User feedback pointed out the asymmetry: the resolution path implicitly assumed "spec is the side to fix", but R7 OQ3 ratification says PRD ↔ spec is **upstream/downstream symmetric** — either side could be the wrong one.

R11.1 (same-day patch, no version bump from `0.9.6`):

- After choice (a), display the matching sibling section, then ask a follow-up `AskUserQuestion` with **4 equal-weight options**:
  - **(i) Sibling is stale → fix sibling now** (inline-execute the relevant `*-update` command in the main thread, same pattern as `/super-manus:drive`)
  - **(ii) Sibling is stale → fix sibling later** (record `acknowledged-soft: <prd|spec>-edit-deferred`)
  - **(iii) My edit was wrong → revert/refine MY edit now** (inline-execute another pass of the SAME `*-update` command on the bullet just edited; `acknowledged-soft: <prd|spec>-edit-revised`)
  - **(iv) Both correct in their voices** (`acknowledged-soft: confirmed-consistent`)

- Inline-execution discipline: read the chained command's `commands/*.md` body, execute its instructions in the main thread. Do NOT spawn a sub-Skill or nest slash commands. Same pattern as `/super-manus:drive`'s "execute the chosen command's body directly" rule.

- Resolution-precedence rule: when the user picks (i) or (iii), the chained command's own logging (`spec-update: <section>` or `prd-update: <option-letter>`) takes precedence over R11's `acknowledged-soft:` value. Don't double-write.

- Edit-irreversibility caveat: option (iii) must surface that the user's original `Edit` tool call cannot be auto-reverted (Edit is destructive). They either tighten the bullet further OR manually restore the prior wording inside the new prd-update / spec-update flow.

The patch lands symmetrically on both `commands/prd-update.md` and `commands/spec-update.md`. Tests extended in both files to assert all 4 options + inline-execution discipline + Resolution-precedence + Edit-irreversibility caveat.

This honors the R7 OQ3 ratification verbatim: PRD ↔ spec is upstream/downstream, neither is master/slave; the user always picks which direction to resolve in.

## R12. test-writer Reflexion injection (writer-tier extension of v0.9.4 R6)

### Observation

v0.9.4 R6 implemented Reflexion-style cross-update memory but only wired it into `impl-architect`. The reflection collection mechanism (`sm_collect_reflections` in `hooks/lib.sh`) is reader-agnostic — it filters by phase keyword + files_touched overlap, not by reader type. Test-writer can consume the same collection with a different reading lens (test-relevant Heuristics: fixture realness / mirror-test traps / edge-case coverage / e2e completion signals) and the same value compounds.

### Why test-writer specifically (not also code-writer / reviewer)

Per v0.9.5 dogfooding analysis (logged in conversation, not in this design doc):

- **test-writer**: ✅ Recurring failure modes are pattern-based (vacuous test, inline-dict fixture, mirror-test reflex, missed e2e). Reflexion catches exactly these. **Direct fit.**
- **code-writer**: ❌ Recurring failure modes are mostly mechanical (commit scope, scope drift), already addressed by v0.9.4 R4's mechanical commit-hygiene checks. Reflexion's behavioral nudges have low marginal ROI on top of mechanical guardrails.
- **reviewer**: ❌ Already reads `findings.md ## Errors` with `attempt_number` discrimination — a different feedback channel that already prevents repeating its own previous round's verdict. Adding `## Reflections` would be confusion of concerns.

R12 ships test-writer only. code-writer and reviewer extensions are NOT planned; if real-world data shows R4's mechanical checks miss a pattern, revisit then.

### Proposed shape (shipped)

#### Reuse pattern

`commands/impl.md` Step 3 (test-writer spawn) reuses architect Pass 2's already-computed `prior_reflections` value. Don't recompute — the underlying findings.md hasn't changed between architect close and test-writer spawn (only architect's plan was committed; findings.md ## Reflections section is touched only at phase close, which hasn't happened yet).

The test-writer's spawning prompt gains one input:

```
- prior_reflections: <verbatim ## Reflections section text from sm_collect_reflections, or "(none)">
```

The spawning instruction explicitly hints at the test-relevant reading lens:

> If `prior_reflections` is non-empty, scan for test-relevant Heuristics (fixture realness / edge case coverage / mirror-test traps / e2e completion signals) and honor each — see `## Honor prior_reflections` in your persona.

#### Persona section

`agents/impl-test-writer.md` gains a new `## Honor prior_reflections (v0.9.6 R12)` section before `## Run protocol`. Four steps:

1. Filter for test-relevant Heuristics (4 categories enumerated)
2. Honor each that applies (write the test it implies, or extend an existing one)
3. Disregard explicitly when warranted (silent ignore wastes the cross-phase memory — same provenance discipline architect uses)
4. Provenance reading: same-update vs cross-update applicability (translation may be required for cross-update Heuristics)

The architect's prior_reflections protocol (v0.9.4 R6) and test-writer's are intentionally parallel — same data source, different reading lens, same explicit-justification-on-disregard rule.

### Tests

- `tests/test_agent_impl_test_writer.sh` extended: assert `prior_reflections` input documented, Heuristic line referenced, cross-update nature, test-relevant Heuristic categories enumerated, `## Honor prior_reflections` section heading exists, provenance handling, explicit-justification rule.
- `tests/test_command_impl_logic.sh` extended: assert Step 3 spawning prompt injects `prior_reflections`, hints at test-relevant categories, reuses architect's already-computed value (don't recompute).

### Open questions (deferred)

1. **Different filter parameters per writer-tier?** Currently test-writer reads the SAME filtered collection as architect (filtered by phase_name keywords + files_touched). Test-writer might benefit from additional filters (e.g., entries with `keywords` containing test-relevant tokens like `fixture`, `coverage`, `e2e`). Defer — reading-lens filter inside the persona is sufficient for now; orchestrator-side pre-filter is a future optimization.
2. **Should orchestrator inject only test-relevant entries?** This would require keyword-based pre-filtering at injection time. Defer — current shape lets test-writer do the filtering with full context (heading + body), which is more robust than mechanical pre-filter.

## Cross-cutting concerns

1. **R11 + R12 ship together but are independent.** R11 touches `commands/prd-update.md` + `commands/spec-update.md` + their tests. R12 touches `agents/impl-test-writer.md` + `commands/impl.md` Step 3 + their tests. Zero file overlap; either could ship alone. They share the v0.9.6 release for batching efficiency.

2. **No template changes.** Both R-items are behavioral additions (new procedure sections in personas + new orchestrator steps). No `templates/*.md` modifications, no `drift_log.md` schema changes, no `findings.md ## Reflections` format changes. Backward-compatible at the on-disk layout level.

3. **No new helpers.** R12 reuses `sm_collect_reflections` from v0.9.4 R6 verbatim. R11 implementation is inline in the two commands' markdown — token extraction + grep are simple enough that adding a helper to `hooks/lib.sh` would be premature abstraction.

4. **Tests added but no schema migrations.** v0.9.5 had 46 tests; v0.9.6 keeps the same test count + extends 4 existing test files with additional assertions. No new test files.

## Status

**Design ratified AND implemented in v0.9.6 (single-shot release).** Both R-items shipped together — see `plugin.json` version `0.9.6` and the matching test extensions.

What landed:

- **R11** — `commands/prd-update.md` + `commands/spec-update.md` each gained a `## Post-edit topic-overlap check` section. Detection: tokenize edited bullet → grep sibling H2 sections → ≥3-distinct-token hit threshold → `AskUserQuestion` with 3 options. Logging: `acknowledged-soft: <variant>` Resolution preserves audit trail without entering Pass 3 hard gate (R7 OQ3 honor); user can manually escalate to `pending` if they judge a real conflict.

- **R12** — `agents/impl-test-writer.md` gained `prior_reflections` input + `## Honor prior_reflections` procedure section. `commands/impl.md` Step 3 reuses architect Pass 2's already-computed value. Same data source as architect's R6 injection, different reading lens (test-relevant Heuristics: fixture realness / mirror-test traps / edge-case coverage / e2e completion signals).

Test counts: 46 of 46 tests pass on the v0.9.6 commit (same count as v0.9.5; the deltas are extensions to 4 existing test files with R11 + R12 assertions, no new test files).

Ratified design decisions:

- **R11** — soft warning, NOT hard drift. R7 OQ3 honor maintained: `acknowledged-soft:` Resolution variants don't enter Pass 3's pending count. User can escalate to `pending` if they judge real conflict.
- **R12** — test-writer only (not code-writer, not reviewer). Reuses `sm_collect_reflections` verbatim; orchestrator passes the same value architect Pass 2 received.

Not in scope (deferred to future R-items if real-world data shows need):

- Code-writer Reflexion injection — covered mechanically by v0.9.4 R4 already
- Reviewer Reflexion injection — different channel (`## Errors` + `attempt_number`) already
- End-of-update gate Pass 1.5 PRD-spec consistency check (Tier 2 from the v0.9.6 design discussion) — defer; edit-time R11 is the cheaper detection point
- `/super-manus:drive` PRD-spec lightweight sweep (Tier 3) — defer; ROI unclear
- Stopword list maintenance / LLM-judgment fallback for borderline overlap (R11 OQ1 + OQ2)
- Per-writer pre-filter on `sm_collect_reflections` (R12 OQ1 + OQ2)
