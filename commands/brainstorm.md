---
description: PRD-led 6-question brainstorm — write project-global prd/_index.md and per-module prd/<module>.md stubs (does NOT seed an update folder; user runs sync after audit)
---

The user wants to brainstorm a project into a PRD folder. v0.4 is project-global — there is no per-feature wrapper.

## Setup

Confirm `docs/super-manus/prd/` is a directory. If absent, tell the user super-manus is not enabled in this project and suggest running `/super-manus:start` first; then stop.

Read the existing `docs/super-manus/prd/_index.md` and any existing `docs/super-manus/prd/*.md`. If `prd/_index.md` already has substantive content (any of `## Problem`, `## Demo`, `## Must` is non-empty / non-placeholder, OR the `## Modules` table has rows), ask once: "PRD already exists. Refine in place (default) or replace from scratch?" Then proceed accordingly. Refine-in-place means: keep what's there, surgically extend or correct.

## The 6 questions (one per turn, in order)

Ask ONE question at a time. Wait for the user's answer before the next. Maximum 6 questions total. Skip a question only if the user already answered it implicitly.

1. **Problem + audience** — "In one sentence: what pain are we relieving, and for whom (primary user + any secondary user)?" The audience answer feeds `_index.md ## Audience`; the pain feeds `_index.md ## Problem` and seeds each module's `## Why this exists`.
2. **Users + trigger + success** — "For the primary user, what moment makes them reach for this, and what does 'this is working for me' look like — 3 measurable outcomes (not 'tests pass' / 'uptime')?" The trigger feeds per-module `## Users`; the 3 outcomes feed `_index.md ## Success metrics` and per-module `## Success`.
3. **Demo** — "Walk me through 3–5 lines of how someone uses this, second-person concrete. If unsure I can offer A) ... and B) ... — just pick one." Offer 2 alternatives only if the user is uncertain; otherwise just take their description.
4. **Must vs Not doing** — "List the must-have capabilities (3–7 short lines), then anything you want to explicitly NOT do that someone might assume is in scope." The Musts seed each module's `## What users get`.
5. **Risks** — "What's the single biggest risk you see — product (wrong abstraction / users don't want it), technical (perf cliff / known-hard problem), or org (waiting on another team / external API)? One sentence; you can name more than one if obvious." Feeds per-module `## Risks`. If the user has none, leave the section terse — don't invent risks.
6. **Modules** — "What system modules should this split into? Suggest 1–3 candidates yourself based on the Must list (e.g. `db / api / frontend / cli`); user confirms or edits. Each module name must be lowercase kebab-case (matching `^[a-z0-9][a-z0-9-]*$`)."

After the 6 (or fewer if the user converged early), optionally probe ONCE for cross-module data flow: "How do these modules connect? One paragraph." If the user can't articulate it, leave it blank.

## Hard constraints

- **Do NOT** ask about database schemas, API endpoints, libraries, frameworks, performance budgets, or implementation architecture. Those belong in per-module `prd/<module>.md ## What users get` (which the user fills after this command, or refines via `/super-manus:prd-update`) and the active update's `tasks/p<n>_impl.md ## Approach` per phase.
- **Do not propose architecture** in your follow-ups. Stay in product semantics.
- Target **~700 words of prose** for the final `prd/_index.md` — soft scannability cap, not a hard limit. Fenced code blocks (e.g. ```mermaid) and markdown tables don't count toward this; don't sacrifice clarity to satisfy `wc -w`.
- Target **~2000 words of prose** for each per-module `prd/<module>.md` stub — same soft-cap semantics. The stub can be terse; the user will flesh it out later.
- One question per turn. Don't bundle.

## Writing the PRD folder

When you have answers (or 6 turns elapsed), write the following files. Use the `prd_index.md` and `prd_module.md` templates as starting structure (their headings are stable: `## Problem` / `## Audience` / `## Success metrics` / `## Demo` / `## Must` / `## Not doing` / `## Modules` / `## Data flow overview` for `_index.md`; `## Why this exists` / `## Users` / `## Success` / `## What users get` / `## How it connects` / `## Quality bar` / `## Risks` / `## Out of scope` / `## Open questions` for each module file).

1. **`docs/super-manus/prd/_index.md`** — replace the seeded placeholder with the user's answers.
   - `## Problem` — question 1's pain sentence.
   - `## Audience` — question 1's primary + secondary user, plus question 2's trigger moment for the primary user.
   - `## Success metrics` — top 3 of question 2's outcomes, each as `<name> — target <X>, measured by <Y>`. If the user gave fewer than 3, leave the rest as `(audit — fill in)` placeholders rather than inventing.
   - `## Demo`, `## Must`, `## Not doing` — questions 3 and 4 verbatim.
   - `## Modules` table with one row per module, columns `| Module | File | Purpose |`, with `File` as a relative link `[prd/<module>.md](<module>.md)` and `Purpose` as a one-line summary.

2. **`docs/super-manus/prd/<module>.md`** for each module — copy from `templates/prd_module.md`, substitute `<module name>` with the actual module name, and pre-fill:
   - `## Why this exists` — 2 sentences, PM voice. Adapt question 1's pain to this module's slice (the share of the user pain this module owns + the business value).
   - `## Users` — question 2's trigger moment, narrowed to who calls this module. If the module is internal-only (e.g. `db`), name the upstream module(s) as the user.
   - `## Success` — pull the user-facing outcomes from question 2 that this module is on the hook for. 3–5 bullets if the user gave enough; fewer is fine. Never "tests pass".
   - `## Risks` — if the user mentioned a risk in question 5 that lands on this module, drop it under the appropriate Product / Technical / Org bullet. Otherwise leave the section as `<placeholder>` for the user to fill — do NOT invent risks.
   - Leave `## What users get`, `## How it connects`, `## Quality bar`, `## Out of scope`, `## Open questions` as light placeholders for the user (or `/super-manus:prd-update`) to flesh out — the brainstorm command must NOT invent schema/endpoint/dependency content here.

3. **`docs/super-manus/roadmap.md`** — under `## Modules`, add one row per module: `| <module> | not-started | |`. Drop the `<module-a>` placeholder if it's still there (it shouldn't be after the seed, but be defensive).

Use the user's answers verbatim where possible. Keep each section terse — Problem and Demo are 1–3 sentences; Must / Not doing are bullet lists.

## After the PRD lands — do NOT auto-seed an update folder

Tell the user:

> PRD seeded: `prd/_index.md` + `<N>` per-module files at `docs/super-manus/prd/`. Roadmap rows added at `not-started`.
>
> Next steps:
> 1. Audit each `prd/<module>.md` and flesh out `## What users get`, `## How it connects`, `## Quality bar`. The brainstorm pass left these light on purpose.
> 2. When a module is ready to start, run `/super-manus:sync <module>` to scaffold the first MVP update folder under `impl/<module>/`.
> 3. Run `/super-manus:drive` if you'd rather have me decide what to do next.

Read `prd/_index.md` and the per-module files you wrote so they are in context for the next agent turn. Do not propose architecture or seed any `impl/` folder — that's `/super-manus:sync`'s job once the user has audited the PRD.
