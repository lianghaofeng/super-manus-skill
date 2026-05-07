---
description: Structured edit on a single prd/<module>.md — add a new capability, tighten/split/demote/exclude an existing bullet. Forward iteration ("add a feature") or drift absorption (resolve a pending prd_drift row). Single-section minimum edit, no changelog markers.
---

This command performs ONE structured edit on a single `prd/<module>.md`. Two trigger contexts share the same 5-option workflow:

- **Forward iteration** — user wants to add a new `## What users get` bullet, tighten an existing one, or extend `## Quality bar` BEFORE any code is written. There is no drift to absorb; this is normal product evolution. After the edit, run `/super-manus:sync <module>` to scaffold the implementation milestone.
- **Drift absorption** — user has decided that PRD should move (rather than the implementation reverting) to resolve a `pending` row in `prd_drift.md`. The edit restores PRD ↔ implementation alignment.

Either mode produces a single-section, single-line edit with no changelog markers — `prd/<module>.md` stays a current-state product snapshot. The orchestrator detects which mode applies from `prd_drift.md` and adapts the lead question + post-edit bookkeeping accordingly.

## Setup

Confirm `docs/super-manus/prd/` is a directory. If absent, tell the user super-manus is not enabled and suggest `/super-manus:start`; then stop.

The user may pass the module as `$ARGUMENTS` (e.g. `/super-manus:prd-update api`). If empty, list `docs/super-manus/prd/<module>.md` files (excluding `_index.md`) and ask the user to pick. The module argument must match `^[a-z0-9][a-z0-9-]*$` and the file `docs/super-manus/prd/<module>.md` must exist.

Read in this order:

1. `docs/super-manus/prd/<module>.md` — full file
2. `docs/super-manus/prd_drift.md` — find the most recent row whose `Module` column matches and `Resolution` is `pending`. **This determines the mode**:
   - Matching row exists → **drift absorption** mode; the row's conflict description is the deviation to absorb.
   - No matching row → **forward iteration** mode; ask the user once: "What edit do you want to make to `prd/<module>.md`? One sentence — the new bullet to add, the existing bullet to change, or the section to extend."
3. The active update for this module (if any) — resolved by the most recently modified subfolder under `docs/super-manus/impl/<module>/`. Read its `task_plan.md ## Goal` and most recent `tasks/p<n>_impl.md ## Objective` if present. In drift mode this grounds the conflict; in forward mode this confirms the new bullet doesn't already exist in flight. If `docs/super-manus/impl/<module>/` is empty (forward mode on a fresh module), skip this step.

## The one question

Ask exactly ONE multiple-choice question, then write. Do not bundle, do not follow up with architecture questions. The lead phrasing varies by mode; the 5 options are identical.

**Drift absorption mode** lead:
> The conflict is `<one-line restatement of the deviation>`. Should the affected `prd/<module>.md` line be:

**Forward iteration mode** lead:
> Editing `prd/<module>.md` to `<one-line restatement of the user's intent>`. Should it be:

Then in both modes, the same 5 options:

> a) **Tighten** — keep the bullet, narrow the wording so reality fits (or the new intent narrows an existing bullet)
> b) **Split** — replace one bullet with two, separating the original intent from the new capability
> c) **Demote** — move the bullet from `## What users get` (or `## Quality bar`) to `## Open questions`, signalling it's no longer a firm commitment
> d) **Exclude** — move the bullet into `## Out of scope`
> e) **Add** — leave existing bullets alone, append one new bullet under the appropriate section

In forward iteration mode, **Add** is the most common choice (new capability) and **Tighten** is the second most common (refining an existing bullet's wording before code lands). **Demote** / **Exclude** in forward mode usually mean the user changed their mind about scope before building.

The user picks one letter and (optionally) supplies new wording. If they don't, draft it yourself in the user's working language (zh / en) — one short line, second-person concrete tone consistent with the rest of the file.

## Verify the bullet against the actual code (Tighten / Demote / Split only)

Before writing the edit, run the **Drift check protocol** in [skills/using-sm/SKILL.md §4](../skills/using-sm/SKILL.md) on the affected bullet:

- **Tighten** — confirm the narrower wording you're about to write actually matches what the code does. Use **LSP** (`document symbols` on the relevant file, `find-references` on the relevant export) to read the real symbol; cross-check with grep on the file's text. Don't trust the user's framing alone — they may misremember the current behavior. The double-source rule applies: write the tightened bullet only if LSP and grep agree on what the code does today.
- **Demote** — confirm the bullet's capability really is unbuilt / partial before moving it to `## Open questions`. If LSP shows the symbol exists and is referenced, the bullet shouldn't be demoted; push back and offer **Tighten** or **Split** instead.
- **Split** — run the protocol on both halves of the proposed split; both must be confirmable independently.
- **Add** and **Exclude** — no verification needed (Add declares new intent; Exclude removes scope).

If the affected bullet sits inside `## How it connects` Exposes / Consumes preamble, the verification target is the **capability boundary**, not a single symbol. For Tighten / Split: confirm the capability name still matches what crosses the module's boundary by `find-references` on the exported entry (Exposes) or grep imports of the upstream module (Consumes). For Demote: a capability rarely belongs in `## Open questions` — usually the right move is to delete the Exposes/Consumes line entirely if the capability is gone, or to Tighten it if the name is wrong. If the affected line sits in `prd/_index.md ## Data flow overview` edge list, the `(for: <capability>)` annotation must continue to match a real `## What users get` capability bullet on the consuming module — verify by reading that module's PRD.

If LSP is unavailable, fall back to grep + Read alone per the protocol; flag the edit with "LSP unavailable — verification is text-only" in the paired `findings.md` decision entry so the user knows confidence is lower.

## Hard constraints on the edit

- **Single surgical edit**: minimum lines changed. Multi-section rewrites must go through `/super-manus:brainstorm` instead — refuse and redirect if the change would cross more than one section of `prd/<module>.md`.
- **No changelog markers**: do NOT leave `~~strikethrough~~`, "(was: ...)", "updated 2026-05-06", "// changed from X", "moved from <section>" — none of it. The PRD is a current-state snapshot; history lives in `findings.md` and `git log`.
- **Preserve structure**: do not reorder sections, rename headings, or change bullet style. Sections stay: `## Why this exists` / `## Users` / `## Success` / `## What users get` / `## How it connects` / `## Quality bar` / `## Risks` / `## Out of scope` / `## Open questions`.
- **One-liners stay one-liners**: no nested bullets, no parenthetical asides longer than 6 words.
- **Total length ≤ 2000 words for `prd/<module>.md`**. If your edit pushes past that, the change is too big — tell the user this is a `/super-manus:brainstorm` job, not a `prd-update` job, and stop.
- **Product semantics only**: no DB schema *strings*, no library names, no file paths, no line numbers, no code identifiers. Schema sketches at the level of "table X has fields a, b, c" are fine; raw migration code is not. **If the deviation is purely tech-design** (e.g. "we used Redis instead of Postgres for the queue"), the PRD probably shouldn't move at all — the conflict belongs in the active update's `tasks/p<n>_impl.md ## Approach`. Push back: "This looks like a tech-design change, not a product change. PRD shouldn't move. Want me to log it in the update's `findings.md` and stop?"

## Writing the edit

Use the Edit tool on `docs/super-manus/prd/<module>.md` with the smallest old_string / new_string pair that captures the change. Do not rewrite the whole file.

## After the edit lands

Behavior is mode-dependent.

### Drift absorption mode

1. Append one entry to `docs/super-manus/impl/<module>/<latest-update>/findings.md ## Decisions` in the standard 3-line shape:

   ```
   ### <YYYY-MM-DD>: PRD revision (<module>, option <a–e>)
   - Chose: <one sentence: which bullet, what it now says>
   - Why: <one sentence: which active update / phase forced the change>
   - Ruled out: revert implementation to original PRD
   ```

   Keep each line ≤ 1 sentence. No file paths, no code identifiers, no diff snippets.

2. Mark the matching row in `docs/super-manus/prd_drift.md` from `Resolution = pending` to `Resolution = prd-update: <option-letter>`. Keep all other rows untouched.

3. Do **not** write to `docs/super-manus/impl/<module>/<latest-update>/progress.md` — it is hook-managed.

4. Tell the user, in one line: "PRD `<module>` updated — `<section>` `<option>`. Decision logged to `findings.md`. Drift row resolved. Resume the update."

### Forward iteration mode

1. **Skip the findings.md write.** There may be no active update yet (e.g. user is adding a brand-new capability that has no implementation milestone). Forward iteration is normal product evolution; the PRD edit alone is the record. `git log -p prd/<module>.md` is the audit trail.
2. **Skip the prd_drift.md mark.** No pending row exists.
3. Do **not** write to `progress.md`.
4. Tell the user, in one line: "PRD `<module>` updated — added/changed `<section>` `<option>`. Run `/super-manus:sync <module>` to scaffold the implementation milestone for this bullet." (Or "...to extend the active milestone" if `docs/super-manus/impl/<module>/<latest-update>/` exists and is still `iterating` per `roadmap.md`.)

## When to refuse and redirect

- The user wants to rewrite multiple sections → suggest `/super-manus:brainstorm` (replace path).
- The deviation is a tech-design change, not a product change → suggest logging in the active update's `findings.md ## Decisions` only and leaving PRD untouched.
- The PRD already matches reality (no actual conflict found) → say so and stop; don't invent an edit.
- The edit would push `prd/<module>.md` past 2000 words → refuse, suggest `/super-manus:brainstorm`.
