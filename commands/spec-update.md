---
description: Structured edit on a single prd/<module>.spec.md — add a new endpoint, tighten a contract, record a fresh design rationale. Forward iteration ("add a contract") or drift absorption (resolve a pending drift_log.md ## Spec drift row). Single-section minimum edit, no changelog markers, engineering voice.
---

This command performs ONE structured edit on a single `prd/<module>.spec.md` (the v0.9.5 R7 per-module engineering reference). Two trigger contexts share the same workflow, mirroring `/super-manus:prd-update` for the spec layer:

- **Forward iteration** — user wants to add a new bullet under `## Data contracts` / `## Interface contracts` / `## Behavioral contracts`, tighten an existing contract, or record a fresh `## Design rationale` decision BEFORE any code is written. There is no drift to absorb; this is normal engineering evolution. After the edit, run `/super-manus:sync <module>` to scaffold the implementation milestone (or extend the active one).
- **Drift absorption** — user has decided that the spec should move (rather than the implementation reverting) to resolve a `pending` row in `drift_log.md ## Spec drift`. The edit restores spec ↔ implementation alignment.

Either mode produces a single-section, minimal edit with no changelog markers — `prd/<module>.spec.md` stays a current-state engineering snapshot. The orchestrator detects which mode applies from `drift_log.md ## Spec drift` and adapts the lead question + post-edit bookkeeping accordingly.

## Setup

Confirm `docs/super-manus/prd/` is a directory. If absent, tell the user super-manus is not enabled and suggest `/super-manus:start`; then stop.

The user may pass the module as `$ARGUMENTS` (e.g. `/super-manus:spec-update api`). If empty, list `docs/super-manus/prd/<module>.spec.md` files and ask the user to pick. The module argument must match `^[a-z0-9][a-z0-9-]*$`.

## Resolve target

Resolve `SPEC_PATH=docs/super-manus/prd/<module>.spec.md`. If the file does NOT exist, offer to seed it via `AskUserQuestion`:

> `<module>.spec.md` doesn't exist for `<module>`. Create it from the template now (so this edit can land)?
> - **Yes, seed from template** — copy `${CLAUDE_PLUGIN_ROOT}/templates/prd_spec.md` to `<SPEC_PATH>`, substituting `<module name>` with the actual module name; then continue with the edit. Recommended.
> - **No, stop** — emit "Stopped — spec file not present; run `/super-manus:reverse-prd-spec <module> spec` to seed from source, or accept the seed offer above to start blank."

If the user accepts the seed, use Bash + sed to copy the template (it lives outside the project under `${CLAUDE_PLUGIN_ROOT}/`, so use Bash, not Edit):

```bash
sed "s|<module name>|${module}|g" "${CLAUDE_PLUGIN_ROOT}/templates/prd_spec.md" > "$SPEC_PATH"
```

Then proceed.

## Drift check (light)

Unlike `/super-manus:prd-update`'s drift check (which requires LSP + grep cross-check because PRD voice carries product semantics), the spec is engineering voice — it can move with the code. Surface a single soft check:

> Any uncommitted source changes in this module's directory? If yes, your spec edit may collide with in-flight work; consider committing or stashing first.

This is informational only — do not block. Run `git status --porcelain <module-source-dir>` (resolve `<module-source-dir>` from PRD `## How it connects` mentions or grep for the module's package name); if non-empty, surface the file list and ask the user to confirm before continuing.

## Mode auto-detection

Read `docs/super-manus/drift_log.md` and search the `## Spec drift` H2 section (NOT `## PRD drift` — those are PRD-update's concern). Find the most recent row whose `Module` column equals `<module>` AND `Resolution` column is `pending`.

- **Pending row found** → **drift absorption** mode. The row's Conflict cell is the deviation to absorb. Lead question:
  > Spec drift `<one-line restatement of the conflict>`. Resolve by editing `prd/<module>.spec.md` to match reality?

- **No pending row** → **forward iteration** mode. Lead question:
  > What edit do you want to make to `prd/<module>.spec.md`? One sentence — the new bullet to add (under which section), the existing contract to tighten, the design rationale to record.

The user picks/answers. Then ask which section the edit lands in (one of `## Data contracts` / `## Interface contracts → Exposes` / `## Interface contracts → Consumes` / `## Behavioral contracts` / `## Design rationale`); only one section per invocation.

## Constraints during edit

- **Single section per invocation.** Multi-section rewrites must go through `/super-manus:reverse-prd-spec <module> spec` (full re-derivation from source). If the user asks for a multi-section edit, refuse and redirect.
- **No changelog markers.** Do NOT leave `~~strikethrough~~`, `(was: ...)`, dated revision marks, `// changed from X` comments. The spec is a current-state snapshot; history lives in `git log -p prd/<module>.spec.md` and `findings.md`.
- **Preserve H2 structure.** Section names are stable: `## Data contracts` / `## Interface contracts` (with `### Exposes` and `### Consumes` sub-headings) / `## Behavioral contracts` / `## Design rationale`. Do not reorder, rename, or invent new sections.
- **Engineering voice.** Schema sketches, code identifiers, file paths, function signatures, library names, tuning constants are ALLOWED here (this is the explicit difference from PRD voice — that's the whole point of the spec layer). Use markdown tables OR fenced code blocks for schemas (both allowed; persona doesn't enforce one format).
- **`## Design rationale` is human-curated.** The edit may freely add a rationale entry (decision + alternatives considered + why), but the section is never auto-derived from source. Reverse-architect leaves it alone (per R10 section-aware refresh policy); spec-update is the human path to grow it.
- **Word cap soft-check.** Target ~3000 words of prose for `prd/<module>.spec.md` (soft cap; fenced code blocks and markdown tables don't count). If your edit clearly pushes the prose well past that, the change is too big — tell the user this is a `/super-manus:reverse-prd-spec` job (full re-derivation), not a single-section edit, and stop.

## Writing the edit

Use the Edit tool on `<SPEC_PATH>` with the smallest old_string / new_string pair that captures the change. Do not rewrite the whole file.

For sub-headings inside `## Interface contracts`: the section has `### Exposes` and `### Consumes` sub-blocks. Insert the new bullet under the correct sub-heading; do NOT collapse them or move bullets between them silently.

## Post-edit topic-overlap check (v0.9.6 R11)

After the spec edit lands, check whether the edit touches a topic that the sibling `prd/<module>.md` also discusses. PRD and spec are upstream/downstream views of the same module (R7 OQ3 ratification) — they MAY discuss the same behavior, they MUST NOT contradict. This check is an **early-warning radar**, NOT a hard gate. Symmetric to the same check in `/super-manus:prd-update`.

### Detection

1. **Skip if PRD missing or only `_index.md` exists.** If `docs/super-manus/prd/<module>.md` doesn't exist, skip this whole section — the brainstorm/reverse-prd-spec flow will fill it in separately.
2. **Tokenize the edited bullet.** Extract noun/verb tokens (≥4 chars, lowercase, alphanumeric, deduped) from the `new_string` you just wrote. Skip stopwords (same list as `/super-manus:prd-update` post-edit check). Aim for 5-15 candidate tokens.
3. **Scan PRD sections by H2.** Read `prd/<module>.md`. The PRD sections most likely to discuss spec-overlapping topics are `## What users get` (capability promises) and `## Quality bar` (NFRs that map to spec's `## Behavioral contracts`). Also check `## How it connects` (which can echo spec's `## Interface contracts → Exposes/Consumes`). Count distinct token hits per H2 section.
4. **Threshold:** ≥3 distinct tokens hitting a single H2 section's body. Below 3 is noise.

### Action when overlap detected

Use `AskUserQuestion`:

> The spec bullet you just edited shares topic vocabulary with `prd/<module>.md ## <section>`:
>
> **Spec edit:** `<one-line summary of new_string>`
> **PRD section bullets matching:** `<list of 1-3 PRD bullets that share tokens, truncated to 80 chars each>`
>
> What now?
> - **(a) Open PRD to inspect** (recommended) — I'll display the full matching section; you decide what to fix (could be PRD, could be the spec edit, could be neither).
> - **(b) Confirm consistent** — PRD and spec are saying the same thing in different voices; record the cross-check and continue.
> - **(c) Mark as soft-acknowledged** — I'm aware of the overlap; don't open it now.

### After choice (a) — symmetric resolution paths (v0.9.6 R11.1)

If user picks (a), display the full matching PRD section verbatim (`Read` the file, print the section between matched H2 and the next `## ` boundary). Then ask a **follow-up `AskUserQuestion`** with FOUR equal-weight options. Both "fix PRD" and "revert/refine spec" are first-class — the conflict direction is not pre-judged (R7 OQ3 says PRD ↔ spec is upstream/downstream symmetric, not master/slave). This mirrors the prd-update side's follow-up exactly, with the directions flipped.

> After reviewing the PRD section, what's the right fix?
> - **(i) PRD is stale — fix PRD now.** I'll inline-execute `/super-manus:prd-update <module>` against the affected PRD section, with the matching context already loaded (you don't have to re-find the bullet). The prd-update flow runs from "drift absorption" mode; the row's Resolution flips to `prd-update: <option-letter>` per prd-update's own bookkeeping (overrides the `acknowledged-soft:` value this command would otherwise have written).
> - **(ii) PRD is stale — fix PRD later.** I'll record `acknowledged-soft: prd-edit-deferred`. You commit to running `/super-manus:prd-update <module>` before the milestone closes; the row stays out of the hard gate (per R7 OQ3) so it won't block, but the audit trail is preserved.
> - **(iii) Spec edit was wrong — revert/refine the spec edit now.** Re-open the spec bullet you just wrote. I'll inline-execute another pass of `/super-manus:spec-update <module>` against THIS bullet, starting from "what should it actually say?". The drift_log row from this run gets `acknowledged-soft: spec-edit-revised` — your re-edit is the resolution. NOTE: the original `Edit` tool call you made cannot be auto-reverted (Edit is destructive); you'll either tighten the bullet further OR manually restore the prior wording inside the new spec-update.
> - **(iv) Both are correct in their voices.** PRD describes the user-facing promise ("signin returns within 200ms p95"), spec describes the algorithmic semantics that deliver it ("Redis sliding-window rate-limit; 429 with Retry-After"). Same topic, both correct, no conflict. Record `acknowledged-soft: confirmed-consistent`.

Inline-execution discipline (for (i) and (iii)): follow the same pattern `/super-manus:drive` uses — **read the target command's `commands/*.md` body and execute its instructions in the main thread; do NOT spawn a sub-Skill or nest slash commands**. The orchestrator stays in one thread; the user sees one continuous flow with multiple `AskUserQuestion` checkpoints.

**Row-write timing — load-bearing (R11.1).** R11 does NOT write a drift_log row at the moment of overlap detection. The row is written ONLY after the user's final choice is known (either at the top-level `(b)`/`(c)`, or at one of the four `(a)` follow-up options). This avoids two bugs: (1) double-row when chained command (i)/(iii) writes its own row, (2) stale `acknowledged-soft:` orphan if the user abandons mid-flow. The chained command for (i)/(iii) writes its own row from scratch — R11 stays out of `drift_log.md` for those branches entirely.

### Logging — final row written exactly once based on user's terminal choice

The audit trail is exactly ONE row in `drift_log.md`. Where it lives and what its Resolution is depends on the user's terminal choice. **No row is written until the terminal choice is known.**

| User's terminal choice | Where row lives | Resolution value | Hard-gates? |
|---|---|---|---|
| **(b)** confirm consistent (top-level) | `## PRD drift` | `acknowledged-soft: confirmed-consistent` | No |
| **(c)** soft-acknowledge (top-level) | `## PRD drift` | `acknowledged-soft: skipped` | No |
| **(a) → (i)** fix PRD now | (no R11 row — chained prd-update writes its own row in `## PRD drift` with `prd-update: <option-letter>`) | n/a (chained command owns it) | No (until escalated by user) |
| **(a) → (ii)** fix PRD later | `## PRD drift` | `acknowledged-soft: prd-edit-deferred` | No |
| **(a) → (iii)** spec edit was wrong, refine | (no R11 row — chained spec-update writes its own row in `## Spec drift` with `spec-update: <section>`) | n/a (chained command owns it) | No (until escalated) |
| **(a) → (iv)** both correct in their voices | `## PRD drift` | `acknowledged-soft: confirmed-consistent` | No |

If overlap NOT detected (token hit count < 3 in every PRD section), skip this whole logging — silence is the default.

### Manual escalation to hard drift (any branch)

If at any point AFTER the row is written the user re-judges and decides the overlap is a real conflict that SHOULD block end-of-update, they manually edit `docs/super-manus/drift_log.md` and change THAT row's Resolution cell from `acknowledged-soft: ...` to `pending`. drift_log's append-only invariant explicitly permits Resolution-cell mutation (only the cell, not the row itself; do NOT append a new row, that would double-count). The row WILL now gate end-of-update at Pass 3.

### Conflict column format (when R11 itself writes the row — branches (b)/(c)/(a→ii)/(a→iv))

```
(soft) spec-PRD topic-overlap: spec edit '<one-line>' shares vocabulary with PRD ## <section>
```

The `(soft)` prefix is a parser hint for human readers — Pass 3 of the end-of-update gate counts only rows with `Resolution = pending` (case-insensitive equality, NOT substring), so `acknowledged-soft: ...` Resolution values preserve audit trail without blocking roadmap → stable. This honors R7 OQ3 (PRD ↔ spec overlap is not hard drift).

For branches (a→i) and (a→iii), the Conflict column is owned by the chained command, not R11.

### Why this matters here too

The spec-side check exists for the same reason as the PRD-side: a user who tightens spec `## Behavioral contracts` (e.g., changes rate-limit semantics) often forgets to revisit the PRD `## Quality bar` bullet that originally promised the user-facing behavior. Without this radar, PRD silently goes stale. The check fires on edit (the ONLY moment the user is mentally on this module), so they can decide while context is loaded — much cheaper than discovering the inconsistency 3 milestones later via a customer support ticket.

## After the edit lands

Behavior is mode-dependent.

### Drift absorption mode

1. Mark the matching row in `docs/super-manus/drift_log.md ## Spec drift` from `Resolution = pending` to `Resolution = spec-update: <section-name>`. Keep all other rows in both `## PRD drift` and `## Spec drift` untouched.

2. **Skip the findings.md write.** Spec edits don't carry product-decision weight — they record engineering reality. The spec edit itself + `git log -p prd/<module>.spec.md` is the trace. (Contrast with `/super-manus:prd-update` drift absorption, which DOES write a findings.md decision because PRD movement is a product decision.)

3. Do NOT write to `progress.md` — it is hook-managed.

4. Tell the user, in one line:
   > Spec `<module>` updated — `<section>`. Drift row in `## Spec drift` resolved (`spec-update: <section>`). Resume the update.

### Forward iteration mode

1. **Skip the drift_log.md mark.** No pending row exists.
2. **Skip the findings.md write.** Forward iteration is normal engineering evolution; the spec edit alone is the record. `git log -p prd/<module>.spec.md` is the audit trail.
3. Do NOT write to `progress.md`.
4. Tell the user, in one line:
   > Spec `<module>` updated — added/changed `<section>`. Run `/super-manus:sync <module>` to scaffold the implementation milestone (or `/super-manus:impl <module>` to extend the active one).

## When to refuse and redirect

- **Multi-section rewrite** → suggest `/super-manus:reverse-prd-spec <module> spec` (full re-derivation from source).
- **Edit reads as a PRD-level NFR change** (e.g. "tighten signin latency promise from 200ms to 100ms") → push back: this is a PRD `## Quality bar` change, not a spec change. Suggest `/super-manus:prd-update <module>` instead. Spec's `## Behavioral contracts` carries the algorithmic semantics that DELIVER the user-facing promise; the promise itself lives in PRD.
- **Edit would push prose well past ~3000 words** → refuse, suggest `/super-manus:reverse-prd-spec <module> spec`.
- **Edit targets `## Design rationale` but is actually a milestone-scoped decision** (e.g. "we picked Approach B over A for THIS phase") → push back: that belongs in the active update's `findings.md ## Decisions`, not the long-lived spec rationale. The spec rationale is decisions that outlive the milestone (e.g. "this module uses Qdrant not pgvector forever, because ..."). Suggest the user write the milestone decision to `findings.md` instead, and reserve the spec rationale for the cross-milestone version.

## Voice contrast vs `/super-manus:prd-update`

| Property | `/super-manus:prd-update` | `/super-manus:spec-update` |
|---|---|---|
| Target file | `prd/<module>.md` | `prd/<module>.spec.md` |
| Voice | PM (user-facing capabilities, NFRs) | Engineering (schemas, contracts, algorithms) |
| Drift section | `drift_log.md ## PRD drift` | `drift_log.md ## Spec drift` |
| Drift-absorb writes findings.md? | Yes (product decision) | No (engineering reality) |
| Allowed: schema strings, code identifiers, file paths | No (PM voice) | Yes (engineering voice) |
| Word cap soft target | ~2000 words of prose | ~3000 words of prose |
| Drift-check protocol | LSP + grep double-source (PRD verify) | Light: only "any uncommitted changes?" warning |
| Section discipline | One section per invocation | One section per invocation |
| No changelog markers | Required | Required |

The two commands are deliberately separate (R8 OQ1 ratification: "standalone `/spec-update` command, not a `/prd-update --scope=spec` flag"). Each carries its own voice discipline and drift semantics; conflating them would dilute both.
