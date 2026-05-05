---
description: Surgically revise a single prd/<module>.md to absorb a confirmed implementation deviation — minimum edit, no changelog markers
---

The user has decided that a PRD module should move (rather than the implementation reverting). This command makes the smallest edit that restores PRD ↔ implementation alignment for that module, while keeping `prd/<module>.md` readable as a current-state product snapshot.

## Setup

Resolve the active feature folder by reading `.super-manus/active`. The folder is `docs/super-manus/<that-name>/`. If `.super-manus/active` is missing or empty, tell the user there is no active feature and suggest `/super-manus:start` or `/super-manus:switch`; then stop.

If `<feature>/prd/` is not a directory, this is a v0.1 feature — tell the user `/super-manus:prd-update` is v0.2-only and stop.

The user may pass the module as `$ARGUMENTS` (e.g. `/super-manus:prd-update api`). If empty, list `prd/<module>.md` files (excluding `_index.md`) and ask the user to pick. The module argument must match `^[a-z0-9][a-z0-9-]*$` and the file `<feature>/prd/<module>.md` must exist.

Read in this order:

1. `<feature>/prd/<module>.md` — full file
2. `<feature>/prd_drift.md` — find the most recent row whose `Module` column matches and `Resolution` is `pending`. If none, ask the user once: "What's the deviation you want PRD to absorb? One sentence."
3. The active update for this module — resolved by the most recently modified subfolder under `<feature>/impl/<module>/`. Read its `task_plan.md ## Goal` and most recent `tasks/p<n>_impl.md ## Objective` if present, just to ground the conflict.

## The one question

Ask exactly ONE multiple-choice question, then write. Do not bundle, do not follow up with architecture questions.

> The conflict is `<one-line restatement of the deviation>`. Should the affected `prd/<module>.md` line be:
> a) **Tighten** — keep the bullet, narrow the wording so reality fits
> b) **Split** — replace one bullet with two, separating the original intent from the new capability
> c) **Demote** — move the bullet from `## Surface` (or `## Constraints`) to `## Open questions`, signalling it's no longer a firm commitment
> d) **Exclude** — move the bullet into `## Out of scope`
> e) **Add** — leave existing bullets alone, append one new bullet under the appropriate section

The user picks one letter and (optionally) supplies new wording. If they don't, draft it yourself in the user's working language (zh / en) — one short line, second-person concrete tone consistent with the rest of the file.

## Hard constraints on the edit

- **Single surgical edit**: minimum lines changed. Multi-section rewrites must go through `/super-manus:brainstorm` instead — refuse and redirect if the change would cross more than one section of `prd/<module>.md`.
- **No changelog markers**: do NOT leave `~~strikethrough~~`, "(was: ...)", "updated 2026-05-06", "// changed from X", "moved from Surface" — none of it. The PRD is a current-state snapshot; history lives in `findings.md` and `git log`.
- **Preserve structure**: do not reorder sections, rename headings, or change bullet style. Sections stay: `## Purpose` / `## Surface` / `## Data flow` / `## Constraints` / `## Out of scope` / `## Open questions`.
- **One-liners stay one-liners**: no nested bullets, no parenthetical asides longer than 6 words.
- **Total length ≤ 2000 words for `prd/<module>.md`**. If your edit pushes past that, the change is too big — tell the user this is a `/super-manus:brainstorm` job, not a `prd-update` job, and stop.
- **Product semantics only**: no DB schema *strings*, no library names, no file paths, no line numbers, no code identifiers. Schema sketches at the level of "table X has fields a, b, c" are fine; raw migration code is not. **If the deviation is purely tech-design** (e.g. "we used Redis instead of Postgres for the queue"), the PRD probably shouldn't move at all — the conflict belongs in the active update's `tasks/p<n>_impl.md ## Approach`. Push back: "This looks like a tech-design change, not a product change. PRD shouldn't move. Want me to log it in the update's `findings.md` and stop?"

## Writing the edit

Use the Edit tool on `<feature>/prd/<module>.md` with the smallest old_string / new_string pair that captures the change. Do not rewrite the whole file.

## After the edit lands

1. Append one entry to `<feature>/impl/<module>/<latest-update>/findings.md ## Decisions` in the standard 3-line shape:

   ```
   ### <YYYY-MM-DD>: PRD revision (<module>, option <a–e>)
   - Chose: <one sentence: which bullet, what it now says>
   - Why: <one sentence: which active update / phase forced the change>
   - Ruled out: revert implementation to original PRD
   ```

   Keep each line ≤ 1 sentence. No file paths, no code identifiers, no diff snippets.

2. If a row in `<feature>/prd_drift.md` had `Resolution = pending` for this module and matches the conflict, mark its Resolution column as `prd-update: <option-letter>`. Keep all other rows untouched.

3. Do **not** write to `<feature>/impl/<module>/<latest-update>/progress.md` — it is hook-managed.

4. Tell the user, in one line: "PRD `<module>` updated — `<section>` `<option>`. Decision logged to `findings.md`. Resume the update."

## When to refuse and redirect

- The user wants to rewrite multiple sections → suggest `/super-manus:brainstorm` (replace path).
- The deviation is a tech-design change, not a product change → suggest logging in the active update's `findings.md ## Decisions` only and leaving PRD untouched.
- The PRD already matches reality (no actual conflict found) → say so and stop; don't invent an edit.
- The edit would push `prd/<module>.md` past 2000 words → refuse, suggest `/super-manus:brainstorm`.
