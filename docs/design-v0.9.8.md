# super-manus v0.9.8 — engineering wiki layer

**Status: RFC — awaiting ratification.** Four R-items shipped together as one
coherent feature; all additive on top of v0.9.7; no breaking changes; one seed
addition to `/super-manus:start`. `plugin.json` will bump from `0.9.7` to
`0.9.8` on release.

## Context: cross-module engineering wisdom has no home

A dogfooding session running `/super-manus:impl-all` on a `signal` module (10
phases, post-v0.9.7) surfaced the gap. The orchestrator main thread was
**manually** reading `findings.md` files from sibling modules (`M1` and `M2`,
9 reflections total) and injecting them verbatim into the architect's Pass 2
spawn prompt — because there was no other way to get cross-module engineering
wisdom in front of the architect.

The reviewer caught 3 issues at pre-test; 2 were direct violations of those
injected reflections (`datetime.utcnow` deprecated in Python 3.12, fabricated
"196" number, write to non-existent path `apps/<m>/tests/`). The manual
injection clearly worked — but it relied on the orchestrator remembering to do
it, on every spawn, across every module. That's a verbal contract, not an
invariant.

The root cause is in [`hooks/lib.sh:277`](../hooks/lib.sh#L277):

```python
pattern = f"docs/super-manus/impl/{module}/*/findings.md"
```

`sm_collect_reflections` globs only the **current module's** updates. Cross-
module reflections (general engineering wisdom like "Python 3.12 deprecated
`datetime.utcnow`") are invisible to architects working on a different module.
v0.9.4 R6 baked in same-module scope as the only mechanism; cross-module
portability was implicit prompt-educated discipline.

### Why not just glob all modules

The naive fix is `docs/super-manus/impl/*/*/findings.md` + a `scope:
cross-module` meta tag. We rejected it. `findings.md ## Reflections` is a
phase-scoped **incident report** with strong situational flavor ("Misstep /
Root cause / Heuristic"). Mixing two different kinds of content (phase
incidents + project-wide engineering rules) in the same file via a metadata
tag is a two-concerns-one-file anti-pattern. Different lifetimes (phase vs
project), different write voices (auto vs curated), different decay curves
(milestone vs perennial).

### LLM-Wiki pattern as design influence

The Karpathy-shared *LLM Wiki* pattern (LLM-maintained persistent knowledge
base with Ingest / Query / Lint operations) is the template. The key
adaptations to super-manus's pipeline architecture:

- **Schema doc is `CLAUDE.md`** — no separate schema file (super-manus already
  uses CLAUDE.md as the agent-facing schema reference).
- **Raw sources are work artifacts** — git commits, findings, reviewer
  verdicts are produced as side-effect of normal pipeline operation, not
  curated by hand.
- **Query is automatic at fixed pipeline checkpoints** — architect/test-writer/
  code-writer spawn prompts always include the wiki, no user-initiated query.
- **Lint runs on a schedule, not continuously** — end-of-update drift gate
  hosts a non-blocking wiki-lint pass.
- **Promotion gate is human-in-loop** — reviewer flags candidates; user
  confirms via `AskUserQuestion`. Wiki bloat is the failure mode; bot-only
  promotion is the bloat vector.

## R16. `wiki/` directory — project-global engineering rules

### Observation

A project-global engineering wisdom layer is missing. The existing layers
(`prd/`, `roadmap.md`, `drift_log.md`, per-module `<module>.spec.md`) all
answer business or per-module questions. Nothing answers "how do we write code
in this project" — the runtime quirks, naming conventions, fabrication
discipline, fixture patterns that span modules.

### Why it's not in earlier versions

v0.9.4 R6 introduced Reflexion-style cross-phase memory via
`sm_collect_reflections`, scoped to the current module. The scope choice was
correct for v0.9.4 (cross-update within a module is a strict subset of cross-
module and shipped first). The cross-module extension was deferred to a later
version once the same-module mechanism stabilized — v0.9.8 is that extension.

### Proposed shape

#### File location and lifetime

```
docs/super-manus/
├── prd/
├── e2e/
├── roadmap.md
├── drift_log.md
├── wiki/                       ← NEW
│   ├── _index.md               ← LLM-maintained catalog
│   ├── _log.md                 ← append-only event log
│   └── <topic>.md              ← one file per topic (coarse-grained)
└── impl/<module>/<update>/findings.md   ← unchanged
```

Project-global, sibling to `prd/`. Committed to git. Lives for the life of
the project. Files survive milestone churn (unlike `impl/<module>/<update>/`
folders which are time-series).

#### Initial set of topic files

**None.** `/super-manus:start` seeds only `_index.md` and `_log.md` with empty
skeletons. Topic files are created on demand at first promotion. Rationale:
- Prescribing `runtime.md` / `paths.md` / `numbers.md` / `testing.md` / `git.md`
  upfront pretends to know what every project needs.
- An empty `runtime.md` is worse than no file — it implies "we have nothing
  to say about runtime" when actually we haven't tried.
- First promote creates whichever topic file the reviewer named (see R17).

CLAUDE.md will document the **recommended starting topics** as guidance —
documented expectations are not the same as shipped empty files.

#### `_index.md` schema

LLM-maintained catalog. One H2 per topic file, bulleted list of rules with
one-line summary + anchor link.

```markdown
# Wiki index

Cross-module engineering rules. Architect / test-writer / code-writer read
this before drafting code. Promoted from `impl/<module>/<update>/findings.md
## Reflections` via reviewer `wiki-candidate:` flag.

## runtime

- [Python 3.12 datetime](runtime.md#python-312-datetime) — use
  `datetime.now(timezone.utc)` instead of deprecated `datetime.utcnow()`
- [Node 20 fetch](runtime.md#node-20-fetch) — global `fetch()` is available;
  no `node-fetch` import needed

## paths

- [Verify before write](paths.md#verify-before-write) — `pathlib.Path.exists()`
  or `test -e` before writing to a path
```

Regenerated by orchestrator after every promote (re-scan all `wiki/*.md` files
ex `_index.md`/`_log.md`; emit H2 sections from H1 of each topic file; bullet
per H2 rule heading).

#### `_log.md` schema

Append-only. `## [YYYY-MM-DD] <event> | <details>` prefix for grep
parseability (mirrors the LLM-Wiki essay's pattern):

```markdown
# Wiki log

## [2026-05-18] promote | runtime.md / Python 3.12 datetime
- Source: impl/signal/2026-05-15-signal-baseline/findings.md p3
- Reviewer flag: wiki-candidate, topic=runtime
- User decision: accept (wording unchanged)

## [2026-05-18] lint | end-of-update drift gate for signal/2026-05-15-...
- 2 contradictions found, 0 stale, 1 gap
- Output: docs/super-manus/wiki/_log.md (this entry)
```

`grep "^## \[" wiki/_log.md | tail -5` gives recent activity. No structure
inside an entry beyond the heading; body is freeform bullets.

#### Topic file schema

```markdown
# Runtime

## Python 3.12 datetime

`datetime.utcnow()` is deprecated in Python 3.12+. Use
`datetime.now(timezone.utc)` instead.

**Source**: impl/signal/2026-05-15-signal-baseline/findings.md p3 Reflection
bullet 2 (reviewer wiki-candidate, accepted 2026-05-18).

## Node 20 fetch
...
```

- H1 = topic name (matches filename)
- H2 = rule heading (clickable from `_index.md`)
- Rule body: 1-3 paragraphs of prose; engineering voice, code identifiers
  allowed; can include code blocks
- **Source** block at end of each rule — provenance link back to the findings
  entry that birthed it. Mandatory. Lets `wiki-lint` detect orphans.

#### Write barriers

Only orchestrator main thread writes `wiki/*`. Subagents (`impl-architect`,
`impl-test-writer`, `impl-code-writer`, `impl-reviewer`) are read-only on
`wiki/`. Same discipline as `findings.md ## Reflections` (orchestrator-only
write), enforced by agent-prompt convention; `impl-test-writer` and
`impl-code-writer` already lack write access to anything not in their scope.

#### Wiki vs spec decision tree (also goes in CLAUDE.md)

```
判断一条规则归 wiki 还是 spec：

1. 是否绑定某一模块的 data / interface / behavioral contract？
   → spec/<module>.spec.md
   例: "POST /v1/signin 返回 200ms p95"、"auth 用 Redis sliding-window 限流"

2. 是否项目级工程通则（语言/runtime/tooling/纪律）？
   → wiki/<topic>.md
   例: "Python 3.12 datetime API"、"不造假数"、"写路径前 check 存在"

3. 边界——多模块都用但是契约形状的东西？
   → 最相关模块的 spec + wiki 互相 cross-ref
   例: "所有 rate-limit middleware 统一用 Redis SETEX + 1min window"

口诀：spec 回答"这个模块做什么"，wiki 回答"我们在这项目里怎么写代码"
```

### Shipped shape — `/super-manus:start` seeding

`scripts/sm-start.sh` adds two file-creation steps after existing PRD/roadmap/
drift_log seeding:

```bash
seed_if_absent docs/super-manus/wiki/_index.md templates/wiki_index.md
seed_if_absent docs/super-manus/wiki/_log.md templates/wiki_log.md
```

No topic files seeded. Existing super-manus projects upgrading to v0.9.8
re-run `/super-manus:start` (idempotent) to get the two new files. If the
project never promotes any rule, `wiki/` stays a two-empty-file directory and
costs nothing.

### Tests

- `tests/test_template_wiki_index.sh` — frontmatter / required H1, schema text
- `tests/test_template_wiki_log.sh` — frontmatter / required H1, log prefix
  format
- `tests/test_sm_start_seeds_wiki.sh` — `/super-manus:start` creates
  `wiki/_index.md` and `wiki/_log.md` when absent, preserves existing files

### Open questions

- **Topic granularity guidance** — when does a topic split? My recommendation:
  topic file > 300 lines → split, but the split is a user judgment call (not
  an automated lint check). Reviewer can suggest `wiki-candidate: topic=runtime`
  but if `runtime.md` is already 400 lines the orchestrator should surface
  "topic file is large; promote to `python-runtime.md` instead?" via
  `AskUserQuestion`. **Defer to v0.9.9** — initial release ships single-level
  topic files only.
- **Recommended starting topics in CLAUDE.md** — exact list TBD. Probably:
  runtime / paths / numbers / testing / git. Open to expansion.

## R17. Reviewer-flagged Ingest

### Observation

A rule lands in `wiki/` via one path: the `impl-reviewer` at pre-close
(checkpoint #3) recognizes a generalizable lesson in the current phase's
`findings.md ## Reflections` and flags it. The orchestrator then asks the
user via `AskUserQuestion`. No retry-count heuristic, no auto-promote.

### Why reviewer-only (not retries-based)

`retries ≥ N` is an indirect signal. It catches "this lesson cost cycles" but
misses single-RETURN lessons that are still generally true, and false-positives
on phase-specific bugs that happened to need 2 RETURNs. Reviewer is direct
judgment ("does this generalize beyond this phase / module?"). Reviewer is
already reading `findings.md ## Reflections` at pre-close (orchestrator wrote
them right before review #3 fired). Adding one verdict field is cheap.

The cost of false-positive promotion is high (wiki bloat is the long-term
failure mode); the cost of false-negative (a wiki-worthy lesson missed) is
low (it'll show up again in a future phase and the reviewer will flag it then,
or the user adds it manually). Asymmetric cost → conservative gate.

### Proposed shape

#### Reviewer verdict additions

`impl-reviewer` pre-close verdict (today emits `APPROVE` / `RETURN_TO_<writer>` /
`ESCALATE_TO_USER`) gains an optional `wiki-candidates:` YAML block:

```yaml
verdict: APPROVE
wiki-candidates:
  - topic: runtime
    proposed-rule-heading: "Python 3.12 datetime"
    proposed-rule-body: |
      `datetime.utcnow()` is deprecated in Python 3.12+. Use
      `datetime.now(timezone.utc)` instead.
    source: "p4 Reflection bullet 2"
  - topic: paths
    proposed-rule-heading: "Verify before write"
    proposed-rule-body: |
      Always check `pathlib.Path.exists()` before writing to a path.
      Three RETURN cycles in p4 were caused by writing to nonexistent
      `apps/<m>/tests/` paths.
    source: "p4 Reflection bullet 3"
```

Block is optional. Absence means "no candidates this phase" — most phases
will have none. Block coexists with all three verdict types (a `RETURN`
verdict can still surface candidates from prior reflections).

#### Orchestrator promote gate

After phase close (review #3 APPROVE + Verification pass), main thread:

1. Parse reviewer verdict for `wiki-candidates:` block; if absent, skip.
2. For each candidate, run `AskUserQuestion`:
   - Question: "Promote to `wiki/runtime.md`?"
   - Options: `accept` / `reject` / `edit-wording`
   - On `edit-wording`, prompt for revised body via second question
3. For each `accept`:
   - Append rule to `wiki/<topic>.md` (create if absent)
   - Regenerate `wiki/_index.md` from scratch (re-scan all topic files)
   - Append `## [YYYY-MM-DD] promote | <topic>.md / <rule-heading>` entry
     to `wiki/_log.md`, body recording the source `findings.md` path + the
     phase heading the reflection came from
4. For each `reject` / `edit-rejected`:
   - Append `## [YYYY-MM-DD] promote-rejected | <topic>.md / <rule-heading>`
     entry to `wiki/_log.md` (same body shape as `promote`); this is the
     audit trail when reviewer later asks "did we already consider this?"

No source-`findings.md` annotation. No `promoted:` meta marker on the
source entry. The `wiki/_log.md` event log is the **only** provenance
record — it carries enough information (source findings path + phase
heading + wiki destination + user decision) to reconstruct either
direction by grep. Simpler than bidirectional annotation; matches the
single-direction nature of the new findings flow (see next section).

#### Findings injection is now same-update-only

Pre-v0.9.8, `sm_collect_reflections` globbed every `findings.md` under
`docs/super-manus/impl/<module>/*/`, keyword-filtered, and injected top-K
matches as `<prior_reflections>` into the architect spawn. Cross-update
memory was the function's whole point.

v0.9.8 splits that responsibility:

| Channel | Scope | Mechanism | User gate |
|---|---|---|---|
| Same-update findings | current update only | full verbatim `## Reflections` dump (`sm_load_update_reflections`) | none (auto-inject every spawn) |
| Cross-update memory | project-global | wiki (`sm_load_wiki`) | reviewer flag + user accept |

The simplifications cascade:

- **No keyword filter, no K=5 cap** for same-update findings. The current
  update's `## Reflections` section is small (typically 5-15 phases × 0-3
  reflections each); full inject is cheap and avoids the "keyword missed
  a relevant lesson" failure mode.
- **No cross-update glob.** Other updates' findings are no longer scanned.
  Module-local lore that should persist across updates lives in wiki or
  it's lost — an explicit choice, not an accident.
- **No dedup needed.** A reflection promoted to wiki this phase will still
  appear in same-update findings for the rest of THIS update (small token
  cost; rare in practice). It will NOT appear in next update's spawn
  because cross-update injection is gone — the wiki entry is the only
  carrier.
- **`sm_collect_reflections` is replaced** by a much shorter
  `sm_load_update_reflections` (no keyword logic, no sort, no K-cap; just
  extract `## Reflections` from one `findings.md`).

The tradeoff: a reflection that's **module-specific but not wiki-worthy**
(e.g. "rate-limit module's fixture cleanup pattern needs explicit
teardown") loses its cross-update carrier. The first phase of the next
update on this module will re-discover the lesson — at which point the
reviewer either flags it for wiki (graduating it to permanent memory) or
the reflection lives only in that update again. Self-correcting on the
2nd or 3rd repetition; transient loss accepted in exchange for the
cleaner mental model "wiki = cross-update, findings = same-update".

#### Why a single funnel via reviewer (not test-writer / code-writer)

`impl-test-writer` and `impl-code-writer` are also positioned to spot
generalizable lessons. We're keeping the funnel single (reviewer only) for
v0.9.8 to avoid duplicate flags from multiple agents on the same phase. If
dogfooding shows reviewer misses too many candidates, v0.9.9 can open the
funnel to other writers — easier to widen than narrow.

### Tests

- `tests/test_agent_impl_reviewer.sh` — assert `wiki-candidates:` block is
  documented in the agent prompt as optional verdict field
- `tests/test_command_impl_promote_gate.sh` — assert orchestrator main thread
  handles `wiki-candidates:` (acceptance test on the command markdown):
  accept appends to `wiki/<topic>.md` + regenerates `wiki/_index.md` +
  records a `## [date] promote |` line in `wiki/_log.md` with source
  findings path in the body; reject records a `promote-rejected |` line
- `tests/test_hooks_lib.sh` — replace the existing `sm_collect_reflections`
  test cases with `sm_load_update_reflections` tests: absent findings →
  empty; findings with no `## Reflections` → empty; placeholder body
  (`(no reflections yet)`) → empty; populated body → full verbatim dump.
  Also asserts `sm_collect_reflections` is no longer defined (rename
  enforcement, negative regression).

### Open questions

- **`edit-wording` UX** — does `AskUserQuestion` chain (option → second
  question for revised body) work cleanly? May need a follow-up free-text
  prompt rather than a structured option.
- **Reviewer re-flagging the same reflection in a later phase** — without
  source-`findings.md` annotation, reviewer might surface the same
  candidate twice across phases (same lesson, two different phases of the
  same update both produce reflections that hit on it). Orchestrator can
  pre-check `wiki/_log.md` for `promote |` or `promote-rejected |` lines
  carrying the same rule heading and skip the duplicate AskUserQuestion.
  **Defer to implementation**: try without pre-check first; add only if
  dogfooding shows duplicate-flag friction.

## R18. Wiki injection into impl pipeline (Query)

### Observation

A wiki nobody reads is dead. Injection at four spawn points (architect Pass 2,
test-writer, code-writer, reviewer) is where wiki earns its keep — the same
fact-block pattern that v0.9.4 R5 introduced for `existing_code_facts` and
v0.9.5 R7 introduced for `spec_facts`. Three writers consume wiki to honor it;
one reviewer consumes wiki to enforce it.

### Proposed shape

#### `sm_load_wiki` helper

New bash function in `hooks/lib.sh`:

```bash
# Load wiki contents into a fact block for spawn injection.
# Always returns _index.md verbatim (small, complete catalog).
# Additionally returns topic files whose H2 rule headings keyword-match
# phase_name tokens (so architect for a "rate-limit-refactor" phase gets
# rate-limit / redis / middleware rules but not Python datetime rules).
#
# Args:
#   $1 — phase_name (tokenized lowercase, alnum split)
sm_load_wiki() {
  local phase_name="${1:-}"
  [ -n "$phase_name" ] || return 0
  # _index.md unconditional
  if [ -f docs/super-manus/wiki/_index.md ]; then
    echo "## Wiki index"
    cat docs/super-manus/wiki/_index.md
    echo ""
  fi
  # Topic files keyword-filtered
  PHASE_NAME="$phase_name" python3 - <<'PY'
  ... # keyword-match H2 rule headings, return matching topic files verbatim
PY
}
```

Always returns `_index.md` (it's small — one bullet per rule); keyword-filters
topic files to keep spawn prompt size bounded.

#### Four spawn injection points

`commands/impl.md` adds a `<wiki>` fact block to four spawn prompts:

| # | Step | Agent | Role |
|---|---|---|---|
| 1 | Step 1c | `impl-architect` Pass 2 | honor |
| 2 | Step 2  | `impl-test-writer` | honor |
| 3 | Step 4  | `impl-code-writer` | honor |
| 4 | Step 1d / Step 3 / Step 5 | `impl-reviewer` (all 3 checkpoints) | enforce |

Block shape is identical across all four:

```
<wiki>
{{ sm_load_wiki "$phase_name" }}
</wiki>
```

Same status as `existing_code_facts` / `spec_facts` — non-negotiable factual
context. Writer output that contradicts wiki is a defect; reviewer that
misses such a defect has itself failed.

Token cost: full wiki block per spawn is ~10-20KB (4KB `_index.md` + 5-15KB
keyword-filtered topic files). At 3 writers + 3 reviewers per phase = ~60-
120KB injected per phase. Accepted as the price of reviewer being a real
enforcement gate at every checkpoint — tiering reviewer depth was considered
and rejected; correctness-first wins over token-savings here. If dogfooding
shows wiki bloat is the dominant prompt-size driver, revisit in a point
release (likely candidates: tiered injection, on-demand reviewer reads).

#### Explicitly NOT injected

Listed for clarity so future R-items don't relitigate:

- **`impl-architect` Pass 1** — emits only `files_touched` YAML; no content
  drafted, no rule to honor or violate. Wiki injection would add tokens for
  zero behavioral effect.
- **`sync-planner`** — operates at PRD-decomposition layer (phase table
  drafting). Wiki rules apply at implementation time, not phase-naming
  time. A wiki rule "Python 3.12 datetime" doesn't constrain whether a
  phase is named "立起 signal 骨架" vs "scaffold signal module".
- **`reverse-architect`** — generates PRD + spec by reading source code +
  runtime probe. Wiki is **downstream** of spec (spec exists first; wiki
  rules get promoted from later phase findings). Injecting wiki here would
  create a circular dependency in the bootstrap path.

If dogfooding shows one of these would benefit, v0.9.9 can add — easier to
widen than narrow.

#### Agent prompt updates — writers (honor framing)

`agents/impl-architect.md`, `agents/impl-test-writer.md`,
`agents/impl-code-writer.md` each get a new `## Wiki injection` section:

> The `<wiki>` block is project-wide engineering law, promoted via
> human-gated review from prior phases' findings. Treat each rule as a
> non-negotiable constraint on your output — Approach claims (architect),
> test code (test-writer), source code (code-writer) that violate a wiki
> rule are defects, not stylistic choices. If a rule genuinely doesn't apply
> to this phase (different runtime, different surface area), say so
> explicitly in your summary line ("wiki rule X doesn't apply because Y")
> rather than silently ignoring it.

#### Agent prompt updates — reviewer (enforce framing)

`agents/impl-reviewer.md` gets a parallel `## Wiki injection` section with
different framing — reviewer's job is to catch writer violations, not to
honor wiki itself:

> The `<wiki>` block is project-wide engineering law that the writer you're
> reviewing (architect / test-writer / code-writer) was also given. Your
> job at this checkpoint includes verifying the writer's output does not
> contradict any wiki rule. A wiki violation is grounds for
> `RETURN_TO_<writer>` (not `APPROVE`), same severity as a spec violation
> or a test-tamper. If the writer explicitly opted out of a rule with an
> "doesn't apply because Y" line in its summary, judge whether the opt-out
> reason is sound; if not, RETURN. If you find a generalizable lesson in
> the current phase's `findings.md ## Reflections` that's not yet a wiki
> rule, surface it via the `wiki-candidates:` block in your pre-close
> verdict (see R17).

### Tests

- `tests/test_hooks_lib.sh` — add `sm_load_wiki` assertions (returns
  `_index.md` always, filters topic files by keyword)
- `tests/test_command_impl_logic.sh` — assert spawn prompts include `<wiki>`
  block at all **four** injection points (architect Pass 2, test-writer,
  code-writer, reviewer at all 3 checkpoints)
- `tests/test_agent_impl_architect.sh` — assert `## Wiki injection` section
  exists with non-negotiable **honor** framing
- `tests/test_agent_impl_test_writer.sh` — same honor framing assertion
- `tests/test_agent_impl_code_writer.sh` — same honor framing assertion
- `tests/test_agent_impl_reviewer.sh` — assert `## Wiki injection` section
  exists with **enforce** framing (RETURN on wiki violation), distinct from
  the writer honor framing
- `tests/test_command_impl_logic.sh` — also assert wiki is NOT injected
  into Pass 1 architect spawn (negative regression)
- `tests/test_command_sync_logic.sh` and `tests/test_command_reverse_prd_spec_logic.sh`
  — assert wiki is NOT injected into sync-planner / reverse-architect spawn
  (negative regression for the "explicitly NOT injected" list)

### Open questions

- **Keyword filter aggressiveness** — too tight = useful rules hidden; too
  loose = prompt bloat. Initial heuristic: match on rule H2 heading tokens
  ∩ phase_name tokens. May need to also match on rule body keywords if
  dogfooding shows misses.
- **Wiki size at scale** — at 50+ rules across 5+ topics, `_index.md` alone
  is ~50 lines. Architect spawn prompt is already heavy (PRD + spec +
  existing_code_facts + update_reflections + previous_architect_draft).
  Wiki might push it past comfortable limits. **Mitigation**: keyword
  filter applies to topic files only; `_index.md` is one line per rule so
  50 rules = 50 lines, still small. R17's switch to same-update-only
  findings inject (replacing the keyword-filtered cross-update glob)
  actually shrinks the per-spawn token budget on most phases — typical
  current-update reflections section is under 20 lines.

## R19. `/super-manus:wiki-lint` + drift-gate integration

### Observation

Wiki rot — outdated rules, contradictions, orphans, missing rules for
recurring incidents — is the long-term failure mode. The LLM-Wiki essay
calls this out explicitly: humans abandon wikis because maintenance burden
grows. The fix is a periodic lint pass that the user can act on.

### Proposed shape

#### The command

`/super-manus:wiki-lint` — spawn `impl-reviewer` (in new lint mode) against
`wiki/` + recent `findings.md` files + recent commits. Reviewer reads
read-only, emits a candidate report.

#### Five lint checks

1. **Contradiction** — rule A says "use X", rule B says "don't use X"
   (heuristic: shared keyword + opposite verb)
2. **Stale** — rule references a file path / function name / package that
   `grep -r` can't find in current source
3. **Orphan** — rule has never been cited by any phase's `findings.md` AND
   was promoted more than N months ago (default N=6). Possibly never useful;
   may want to retire.
4. **Gap** — `findings.md ## Reflections` across all updates contains a
   recurring misstep that no wiki rule addresses (heuristic: same heading
   tokens appear in ≥3 different updates' Reflections, no matching wiki
   rule). Candidate for promote.
5. **Cross-ref miss** — rule body mentions a concept (`[[other-rule]]`) that
   doesn't resolve to a wiki rule

#### Output format

Reviewer writes findings to `wiki/_log.md` as a lint entry:

```markdown
## [2026-05-18] lint | end-of-update drift gate

- Contradictions: 0
- Stale: 1
  - runtime.md / Node 18 fetch — references `node-fetch` package, no longer
    in package.json (commit abc1234)
- Orphan: 0
- Gap: 1
  - "redis connection pooling" appears in 3 findings (signal/2026-04-01,
    auth/2026-04-15, billing/2026-05-02) — candidate promote to runtime.md
- Cross-ref miss: 0
```

User reads the entry and either:
- Runs `/super-manus:prd-update` or `/super-manus:spec-update` flow for
  Stale/Contradiction findings (rule needs revision)
- Manually edits `wiki/<topic>.md` to retire Orphans
- Triggers a follow-up `/super-manus:wiki-promote <topic> <rule-heading>` for
  Gaps (NEW command — manual promote path for cases where reviewer didn't
  flag at pre-close; details deferred to implementation)

#### Drift gate integration

End-of-update drift gate (today: 3 Passes — refresh drift / e2e coverage /
pending=0) gains **Pass 4: wiki-lint** as a **non-blocking** check. Lint
findings are appended to `wiki/_log.md`; the gate emits a summary line ("wiki
lint: 1 stale, 1 gap — see wiki/_log.md") but does NOT fail-close on lint
findings. Rationale: lint is advisory; auto-blocking a milestone close on a
contradiction finding the human hasn't yet reviewed creates user-unfriendly
release friction.

User can also run `/super-manus:wiki-lint` standalone any time (e.g., monthly).

#### Reviewer reuse vs new lint agent

Reuse `impl-reviewer` with a new `mode: wiki-lint` spawn parameter. Same
read-only stance, same agent definition, just different spawn prompt. Avoids
shipping a new agent file. The orchestrator already knows how to spawn the
reviewer; the only change is the spawn prompt structure.

### Tests

- `tests/test_command_wiki_lint.sh` — assert command exists, spawns reviewer
  in lint mode, writes to `wiki/_log.md`
- `tests/test_skill_using_sm.sh` — assert end-of-update drift gate Pass 4
  documentation mentions wiki-lint as non-blocking

### Open questions

- **Standalone command name** — `/super-manus:wiki-lint` vs `/super-manus:lint`
  vs subcommand of `drive` or `catchup`? Going with explicit `wiki-lint` for
  v0.9.8; can alias later.
- **`/super-manus:wiki-promote`** — manual promote path for cases where the
  reviewer didn't flag at pre-close but the user spotted a rule worth
  promoting. **Defer to v0.9.9** unless dogfooding shows immediate need.
- **Lint cron / hook** — should wiki-lint run on `SessionStart` for projects
  that haven't lint'd in N weeks? Nice-to-have, not v0.9.8.

## Cross-R coordination

R16-R19 ship together as v0.9.8. The R-items are interdependent:

- **R16 alone is dead** — nothing populates the wiki directory.
- **R17 alone is dead** — without R16's schema, nowhere to write candidates.
- **R18 alone is dead** — empty wiki injects empty fact block.
- **R19 alone is dead** — nothing to lint.

So the whole feature ships in one release. The `plugin.json` version bump and
the `/super-manus:start` seed addition are the user-visible signals.

## Out of scope for v0.9.8 (explicitly deferred)

- **Multi-file topics** (`wiki/runtime/python.md` style nesting) — defer until
  a single topic file exceeds 500 lines in dogfooding
- **Wiki-as-PR-blocker** (lint findings auto-fail CI) — defer until lint
  precision is proven
- **Per-project starter wiki templates shipped with plugin** — defer; let
  projects accumulate their own rules organically
- **Embedding-based wiki search** — defer; keyword filter + small `_index.md`
  is enough at moderate scale
- **Obsidian-style backlinks** (`[[rule]]` cross-refs auto-resolved) — defer;
  lint catches broken backlinks as `cross-ref miss`
- **Auto-promotion based on `retries ≥ N`** — explicitly rejected in R17;
  reviewer-flag-only is the entire ingest path for v0.9.8
- **Cross-project wiki sharing** — defer; each project's wiki is local

## Migration

Pre-v0.9.8 projects upgrading:

1. Re-run `/super-manus:start` (idempotent) — creates `wiki/_index.md` and
   `wiki/_log.md` if absent, leaves existing files alone.
2. No retroactive promotion of existing `findings.md ## Reflections` — they
   stay where they are. New ingest path applies from the next phase close
   forward. If users want retroactive promotion, they can manually edit
   `wiki/<topic>.md` (the schema is documented in CLAUDE.md).

No code changes required in user projects. No breaking changes.
