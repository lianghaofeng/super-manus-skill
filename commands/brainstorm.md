---
description: PRD-led light brainstorm — 5 questions max, output a ≤500-word prd.md for the active feature
---

The user wants to brainstorm a feature into a lightweight Product Requirements Doc.

## Setup

Resolve the active feature folder by reading `.super-manus/active`. The folder is `docs/super-manus/<that-name>/`. If `.super-manus/active` is missing or empty, tell the user there is no active feature and suggest `/super-manus:start <name>` first; then stop.

Read the existing `<folder>/prd.md` and `<folder>/task_plan.md`. If `<folder>/prd.md` already has substantive content (any of `## Problem`, `## Demo`, `## Must`, `## Not doing` is non-empty / non-placeholder), ask the user once: "PRD already exists. Refine in place (default) or replace from scratch?" Then proceed accordingly.

## The 5 questions (one per turn, in order)

Ask ONE question at a time. Wait for the user's answer before the next. Maximum 5 questions total. Skip a question only if the user already answered it implicitly.

1. **Problem** — "In one sentence: what pain are we relieving, and for whom?"
2. **Users / trigger** — "Who's the primary user, and what moment triggers them to reach for this?" (a moment, not a job title)
3. **Demo** — "Walk me through 3 lines of how someone uses this, second-person concrete. If unsure I can offer A) ... and B) ... — just pick one." Offer 2 alternatives only if the user is uncertain; otherwise just take their description.
4. **Must vs nice-to-have** — "List the capabilities. Which 3-5 are must-have vs nice-to-have?"
5. **Out of scope** — "Anything you want to explicitly NOT do, that someone might assume is in scope?"

After the 5 (or fewer if the user converged early), optionally probe ONCE for a success metric: "Is there a measurable success criterion you'd want to track?" If the user can't articulate one, skip — leave the slot blank in the PRD.

## Hard constraints

- **Do NOT** ask about technical architecture, database schemas, API design, libraries, frameworks, performance budgets, or implementation approach. Those belong in `tasks/p<n>_impl.md ## Approach` per the using-sm skill — not the PRD.
- **Do NOT** propose architecture in your follow-ups. Stay in product semantics.
- Keep the final `prd.md` under **500 words** total.
- One question per turn. Don't bundle.

## Writing the PRD

When you have answers (or 5 turns elapsed), write `<folder>/prd.md` using the structure already in the file (it was seeded from `templates/prd.md`):

```markdown
# PRD: <feature title>

## Problem
<one sentence>

## Demo
<3–5 lines, second person, concrete>

## Must
- <one-liner each>

## Nice-to-have
- <one-liner each, if any>

## Not doing
- <explicit non-goals>

## Success metric
<one line, or blank>
```

Use the user's answers verbatim where possible. Keep each section terse — Problem and Demo are paragraphs of 1-3 sentences; Must / Nice / Not are bullet lists.

## After the PRD lands

1. Update `<folder>/task_plan.md ## Goal` to a single-sentence summary that ends with a pointer to prd.md, e.g.:
   > Replace the 4-step checkout with single-page approval. See [prd.md](prd.md).
2. Suggest 3–7 phase rows in `<folder>/task_plan.md ## Phases`, derived from the Must list (one phase may deliver one or more Must items). All status `pending`. Tell the user: "Suggested phases — review and edit before running `/super-manus:phase 1`."
3. Stop. Do not propose architecture or write any `tasks/p<n>_impl.md`. The user will run `/super-manus:phase 1` next when ready.
