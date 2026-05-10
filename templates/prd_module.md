<!-- prd/<module>.md: this module's TARGET STATE, written from a product (PM) perspective with engineering evidence appended. NO code, NO file paths, NO line numbers — those live in impl/<module>/<update>/tasks/p<n>_impl.md. No changelog markers (no strikethrough, no "(was: ...)", no dated revision marks): PRD is a current-state snapshot, history lives in git log + findings.md. Target ~2000 words of prose — soft scannability cap, not a hard limit. Fenced code blocks and markdown tables don't count toward this; don't degrade content to satisfy `wc -w`. Headings are stable — hooks, scripts, agents, and tests parse them by exact match. -->
# <module name>

## Why this exists

<2 sentences: the user pain + the business value. PM voice. Not "this module wraps X".>

## Users

<who consumes this module — end-users (parents, students, teachers) or internal actors (other modules, oncall, ops). For each, the persona + the moment they reach for it. 2–4 lines.>

## Success

<what "this module is working" looks like FROM THE USER'S SIDE — measurable. Not "tests pass" / "uptime > 99%". 3–5 bullets, each with a target and how it's measured.>

## What users get

<open with 主要使用场景: list of 2–4 user-facing scenarios this module supports (skip for single-scenario utility modules), then list 3–5 capabilities. Bullet body PM voice; impl evidence (file paths, line numbers, function names, tuning constants) goes in the Backed by: cite, NOT in the bullet body.

Format:

主要使用场景:
- **<场景名>**: <一句话场景描述, PM voice>
- **<场景名>**: <一句话场景描述, PM voice>

实现这些场景的能力:

- **<Capability>** — <PM description: what users can now do>. Backed by: <concrete schema | endpoint | screen | CLI command>.>

## How it connects

<semantic surface first (what capabilities cross this module's boundary), then structural edges (who/protocol). Format:

Exposes:
- <capability name in PM voice> → <consumer module / external actor>

Consumes:
- <capability name in PM voice> ← <provider module / external system>

Upstream (who calls in): <list of modules / external actors>
Downstream (where outputs go): <list of modules / external systems>
Third-party (external): <LLM provider / payment gateway / etc>

Edge list:
- in:  ← <X> via <protocol>
- out: → <Y> via <protocol>

Exposes/Consumes items name PM-voice capabilities ("order placement", "credit-score lookup"), NOT endpoint paths or symbol names. Endpoint detail stays in the Edge list.>

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
