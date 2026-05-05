<!-- prd/_index.md: feature-level overview + module manifest. Per-module surface (schema, interfaces, UX) lives in prd/<module>.md, not here. Total ≤700 words. Headings are stable. -->
# <feature title>

## Problem

<one sentence: what pain, for whom>

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

<text or simple diagram describing how the modules connect at the feature level. Per-module data flow detail lives in each prd/<module>.md ## Data flow.>
