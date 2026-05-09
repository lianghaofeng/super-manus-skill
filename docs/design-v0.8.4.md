# super-manus v0.8.4 — README repositioned as LLM Wiki + PRD-driven development

## 1. What changed from v0.8.3

Pure documentation + positioning release. Zero code, schema, agent, hook, template, or test changes.

- `README.md` hero rewritten around **LLM Wiki + PRD-driven development, in one loop**
- `README.md` Mermaid cycle diagram inserted between hero and the four engineering pillars (visualizes the loop before substance)
- `README.md` ## Updates entry for v0.8.4 added; v0.8.3 demoted from `— current`
- `README.zh-CN.md` mirrored
- `docs/design-v0.8.4.md` (this file) added
- `.claude-plugin/plugin.json` version bumped 0.8.3 → 0.8.4

## 2. The reframing

Pre-v0.8.3, the README opener was *"PRD-driven feature development for Claude Code — engineered so the AI can't fake its way to 'done.'"* — functionally accurate but with no conceptual hook. The four pillars (PRD persistence, reverse-PRD, drift logging, multi-agent auditing) were already structurally aligned with the [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) pattern (LLM-maintained structured markdown, ingest/query/lint operations, three-layer architecture) — but the README never surfaced that mapping.

v0.8.4 makes the mapping explicit. The hero becomes a tagline that names both halves: **LLM Wiki + PRD-driven development, in one loop.** The body explains the fusion: LLM Wiki for knowledge accumulation, PRD-driven development for execution discipline. Knowing → doing → knowing.

### Layer mapping

The structural correspondence between the LLM Wiki primitives and existing super-manus mechanisms (which led to the rejection of a separate `wiki/` directory — see §4):

| LLM Wiki primitive | super-manus mechanism | Pillar |
|---|---|---|
| ingest sources → compile to structured knowledge | `/super-manus:reverse-prd` → compile code into PRD | #2 |
| Wiki pages (compiled spec) | `prd/<module>.md` (target state) | #1 |
| `index.md` (catalog) | `roadmap.md` (auto-managed module status) | — |
| `log.md` (chronological) | `progress.md ## Session log` + `git log` (hook-managed) | — |
| append-only knowledge accumulation | per-update `findings.md ## Decisions` (preserved across the `impl/` time series) | — |
| query → retrieve on demand | `/super-manus:catchup` (re-injects PRD + active update) | — |
| lint (consistency check) | drift detection + end-of-update gate (BLOCKING) | #3 |
| schema | `CLAUDE.md` + skill files (enforced via hooks/tests) | — |
| LLM does the maintenance, human curates | architect/test-writer/code-writer agents + reviewer (read-only) | #4 |

LLM Wiki stops at *knowing*. PRD-driven development adds *doing*. The decisions and lessons that come out of *doing* go back into the knowledge layer (per-update `findings.md`), so the next phase's `impl-architect` starts from a higher floor — that's the loop.

## 3. README structure

The README is restructured to keep the LLM Wiki framing alive throughout the opener — no concept-then-pivot-back-to-concept whiplash:

```
Hero (tagline + 2-sentence loop explanation + LLM Wiki link)
  ↓
Mermaid cycle diagram (visualizes the loop)
  ↓
Bridge: "This loop isn't a philosophy — it's pinned down by 4 engineering pillars:"
  ↓
4 pillars (verbatim from v0.8.3 — the engineering substance)
  ↓
v0.8.4 status note (what changed, what didn't)
  ↓
Self-sufficient note
  ↓
## Install
```

No separate `## What it is` section. The earlier draft had one (with the layer mapping table inside the README), but the table broke the flow — readers had to make two trips through the LLM Wiki framing (once in hero, once in the recap section). Moving the mapping table here (§2 above) keeps the README a continuous narrative; the design doc carries the formal correspondence for readers who want it.

## 4. Why no `wiki/` directory

A natural-feeling extension would be: if super-manus is an LLM Wiki, give it a `docs/super-manus/wiki/` directory with `index.md`, `<slug>.md` pages for architectural decisions, etc. v0.8.4 explicitly rejects this.

The LLM Wiki primitives are already covered by existing files:

- **Pages (compiled knowledge)** → `prd/<module>.md` (with stricter normative discipline than a generic wiki)
- **Index** → `roadmap.md`
- **Log (chronological)** → `progress.md ## Session log`
- **Append-only knowledge** → per-update `findings.md ## Decisions` (preserved in `impl/<module>/<update>/findings.md` across the time series)

Adding a separate `wiki/` directory would create three problems:

1. **Multi-source-of-truth risk** — the same architectural decision could end up in `findings.md` and `wiki/<slug>.md`. Which is canonical when they drift?
2. **Auto-archival paradox** — to avoid (1), the only sensible fill mechanism is automation (agent copies decisions from `findings.md` to `wiki/`). But that's just copying state from one place to another — it doesn't add information.
3. **Pre-built solution to a hypothetical problem** — the only real gap (impl-architect needing cross-update rationale during a new phase) hasn't been observed in practice. `grep -r "## Decisions" docs/super-manus/impl/` works today; if the cost of that ad-hoc lookup proves too high, a future version can revisit. Adding a directory now is YAGNI.

The wiki framing is structural truth, not a missing feature. v0.8.4 surfaces the truth in the README; the directory layout doesn't need to change.

## 5. What's deferred

Possible future work, not committed:

- **v0.8.5 (if it ships)** — only if real, repeated pain materializes around cross-update rationale lookup. The intervention is not a new directory — it's teaching `impl-architect` to grep prior `findings.md` files explicitly when drafting a phase plan that touches a module with prior updates. Reactive, not pre-built.
- **External-source ingestion** — the original LLM Wiki spec covers ingestion of articles/papers/etc. into wiki pages. super-manus has no such use case (sources are codebase + requirements, not literature). Out of scope indefinitely.

## 6. Files touched

```
README.md                                     # hero + Mermaid + bridge sentence + ## Updates entry
README.zh-CN.md                               # same shape, mirrored
docs/design-v0.8.4.md                         # this file
.claude-plugin/plugin.json                    # version 0.8.3 → 0.8.4
```

## 7. Migration

None. Pure documentation change. Existing `docs/super-manus/` layouts continue to work without touching anything. v0.8.3 architecture (4-agent pipeline + 3 review checkpoints, passive runtime probe, per-agent model routing) is unchanged.

## 8. Tests

No test contract changes. `tests/run-all.sh` is expected to remain green with no test edits. `tests/test_docs_present.sh` already asserts `## Install`, `## How to use it`, `## Directory layout`, `## Updating an existing PRD`, `## Drift detection`, `## Updates` — all still present.
