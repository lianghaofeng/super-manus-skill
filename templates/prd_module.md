<!-- prd/<module>.md: this module's TARGET STATE. Schema sketches, interface outlines, UX skeletons all OK in ## Surface. NO code snippets, NO file paths, NO line numbers — those live in impl/<module>/<update>/tasks/p<n>_impl.md. No changelog markers (no strikethrough, no "(was: ...)", no dated revision marks): PRD is a current-state snapshot, history lives in git log + findings.md. Total ≤2000 words. Headings are stable. -->
# <module name>

## Purpose

<one sentence: what role this module plays in the feature>

## Surface

<the shape this module presents to users / other modules / itself: tables and field lists, endpoint paths and shapes, screens / flows. Target state, not migration steps.>

## Data flow

<who calls in, where outputs go, ordering / timing constraints if any>

## Constraints

<non-negotiables: perf budgets, compat rules, security boundaries, must-have test coverage targets>

## Out of scope

<what this module won't do, even if adjacent>

## Open questions

<unresolved product questions tracked here so they don't pollute findings.md; remove the bullet once answered>
