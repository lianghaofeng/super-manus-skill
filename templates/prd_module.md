<!-- prd/<module>.md: this module's TARGET STATE, written from a product (PM) perspective with engineering evidence appended. NO code, NO file paths, NO line numbers — those live in impl/<module>/<update>/tasks/p<n>_impl.md. No changelog markers (no strikethrough, no "(was: ...)", no dated revision marks): PRD is a current-state snapshot, history lives in git log + findings.md. Total ≤2000 words. Headings are stable — hooks, scripts, agents, and tests parse them by exact match. -->
# <module name>

## Why this exists

<2 sentences: the user pain + the business value. PM voice. Not "this module wraps X".>

## Users

<who consumes this module — end-users (parents, students, teachers) or internal actors (other modules, oncall, ops). For each, the persona + the moment they reach for it. 2–4 lines.>

## Success

<what "this module is working" looks like FROM THE USER'S SIDE — measurable. Not "tests pass" / "uptime > 99%". 3–5 bullets, each with a target and how it's measured.>

## What users get

<top 3–5 capabilities the module delivers, PM voice first, technical evidence appended. Format:
- **<Capability>** — <PM description: what users can now do>. Backed by: <concrete schema | endpoint | screen | CLI command>.>

## How it connects

<dependencies in plain language, then a precise edge list.
- Upstream (who calls in): <list of modules / external actors>
- Downstream (where outputs go): <list of modules / external systems>
- Third-party (external): <LLM provider / payment gateway / etc>

Edge list:
- in:  ← <X> via <protocol>
- out: → <Y> via <protocol>>

## Quality bar

<non-functional requirements that are user-visible — perf, scale, compliance, availability, data freshness. Not internal infra ("uses Postgres") — that's implementation detail. 3–5 bullets, each measurable.>

## Risks

<what could derail this module's success, three flavors:
- **Product**: <user might not actually want this / wrong abstraction>
- **Technical**: <perf cliff / dependency outage / known-hard problem>
- **Org / dependency**: <waiting on another team / external API change>
2–4 bullets total.>

## Out of scope

<explicit non-goals; what reviewers might assume but isn't in scope>

## Open questions

<each item: [decide|clarify|measure] <question>. Resolution: <what input would resolve it>. Remove the bullet once answered.>
