<!-- prd/_index.md: feature-level PRD. PM-led system overview with audience, success metrics, and a runtime architecture diagram. Per-module surface (capability lists, schemas, dependency edges) lives in prd/<module>.md. Total ≤700 words. Headings are stable — hooks, scripts, agents, and tests parse them by exact match. -->
# <feature title>

## Problem

<one sentence: what pain, for whom>

## Audience

<the system's primary users + secondary users.
- **Primary**: <persona> — when they use it, why
- **Secondary**: <persona> — when they use it, why>

## Success metrics

<top 3 KPIs that say the system is working. User / business metrics, not infra metrics. Each: name, target, how measured.>

## Demo

<3–5 lines, second person, concrete usage scenario: "you open ... see ... click ... system responds with ...". No architecture, no API.>

## Must

- <one-liner each; aim for 3–7 items at the feature level>

## Not doing

- <explicit non-goals; what reviewers might assume but isn't in scope>

## Modules

| Module | File | Purpose |
| --- | --- | --- |
| <module-a> | [prd/<module-a>.md](<module-a>.md) | <one line> |

## Data flow overview

<ASCII architecture diagram (box-drawing characters: ┌ ┐ └ ┘ ─ │ ▲ ▼ ◄ ►) + edge list backup + offline-modules line + 1–2 sentence loop summary. Edge list format: `<A> --<protocol>--> <B> [path/topic] (for: <capability>)` — the `(for: ...)` parenthetical names the PM-voice capability the edge carries, matching the vocabulary used in each prd/<module>.md ## How it connects Exposes/Consumes block. Per-module data flow detail lives in each prd/<module>.md ## How it connects.>
