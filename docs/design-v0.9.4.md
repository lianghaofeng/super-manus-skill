# super-manus v0.9.4 — deferred items log

This file is a forward-looking RFC, NOT a shipped release. Items recorded here are deferred design ideas surfaced during v0.9.3 dogfooding. Each entry stays here until either (a) it ships in a v0.9.x release (move "Status" inline) or (b) it's rejected (record rejection inline). Do NOT implement any item below without a separate user "ship it" directive.

Versioning convention: when an R-item ships, `plugin.json` bumps to `0.9.4` (or later). On ratification the "NOT yet ratified" status flips inline per R-item, same pattern as `design-v0.9.3.md`.

## Context: two real bugs from v0.9.3 dogfooding

Both surfaced in the same `/super-manus:impl` run (P3 retry loop):

1. **`impl-code-writer` swept unrelated WIP into a phase commit** — used `git add <whole-file>` while the user's working tree was dirty with unrelated edits (README work, etc.). The phase commit ended up containing files outside `## Files touched`. No test caught it because hash check only protects `tests/`.

2. **`impl-architect` was "state-blind" across re-spawns** — wrote `## Approach: add foo()` four phases in a row while `foo()` already existed in source (a prior buggy version). Reviewer caught it each time (RETURN_TO_ARCHITECT × 4, hitting the retry budget). Reviewer's specific 6 fix-points were in `previous_attempt_feedback`, but architect re-spawn kept producing "add" instead of "replace". Root cause: v0.9.3 feeds reflections + reviewer feedback as **advisory text**; sonnet reads "must grep verify" ≠ sonnet actually greps.

The framework's current safety net is the reviewer alone — fine when it catches once, costly when the same bug repeats. Both bugs point at the same gap: **persona text is too soft; orchestrator-enforced fact injection is needed.**

## R4. code-writer commit hygiene + whitelist mechanical check

### Observation

`impl-code-writer`'s `## Commit` section says "commit ONLY source files". Real-world: the writer used a broad `git add` (file-level, not hunk-level) while the working tree had unrelated dirty files. Those files got swept into the phase commit. The phase still passed (tests green, hash check green) but the commit was contaminated.

### Why it's not in v0.9.3

v0.9.3 trusts persona text + the test-hash cheat-prevention check. The hash check protects `tests/` from being edited; it does NOT protect against staging unrelated source files. There's no white-list enforcement on what code-writer is allowed to commit.

### Proposed intervention — two-layer defense

#### Layer 1 — persona rule (advisory)

Add to `agents/impl-code-writer.md ## Commit`:

- Before each commit, run `git status --porcelain` and read it.
- Only stage files explicitly listed in `${UPDATE_DIR}/tasks/p<n>_impl.md ## Files touched`.
- Use `git add <specific-path>` per file. NEVER `git add .`, `git add -A`, `git add <dir>/`, or `git add <wildcard>`.
- If working tree contains files outside `## Files touched` that are dirty (modified by user or prior session), STOP and return an `OUT_OF_SCOPE_DIRTY` summary line. Do not stash, do not unstage, do not commit. Let the orchestrator decide.

#### Layer 2 — orchestrator mechanical check (load-bearing)

In `commands/impl.md` Step 5 (code-writer spawn), wrap the spawn with snapshot + post-check:

```bash
# Pre-spawn: snapshot baseline + parse whitelist
git status --porcelain > "$UPDATE_DIR/.pre_codewriter_status_p<n>.txt"
WHITELIST=$(parse_files_touched "$UPDATE_DIR/tasks/p<n>_impl.md")
# WHITELIST excludes anything under tests/ or e2e/ (implicit deny — code-writer commits source only)

# Spawn code-writer ...

# Post-spawn: check every staged-or-committed file against whitelist
STAGED=$(git diff --cached --name-only)
NEW_COMMITS=$(git log --name-only --pretty=format: ${PRE_HEAD}..HEAD | sort -u)
for f in $STAGED $NEW_COMMITS; do
  if ! whitelist_match "$f" "$WHITELIST"; then
    echo "STAGE VIOLATION: $f not in ## Files touched"
    VIOLATION=1
  fi
done
[ -n "$VIOLATION" ] && reject_via_AskUserQuestion
```

On violation, orchestrator surfaces an `AskUserQuestion`: "Code-writer staged/committed files outside `## Files touched`: [list]. Choose: (a) Reset and re-spawn code-writer, (b) Accept (architect drift — update `## Files touched`), (c) Abort phase." No silent auto-reset.

### Pre-existing dirty WIP

If `git status --porcelain` BEFORE code-writer spawn shows files dirty that overlap with whitelist OR are in tests/e2e: orchestrator surfaces `AskUserQuestion` first — "Working tree has uncommitted changes that overlap with this phase's scope. Choose: (a) Stash → spawn → unstash, (b) Commit your WIP first, (c) Continue anyway (you accept the contamination risk)." Default to (b).

### Tests

- `tests/test_agent_impl_code_writer.sh` extended:
  - Assert persona contains "`git status --porcelain`" + the whitelist-only-staging rule + `OUT_OF_SCOPE_DIRTY` return contract.
  - Assert ban of `git add .` / `git add -A` appears verbatim.
- `tests/test_command_impl.sh` extended (or new):
  - Assert `commands/impl.md` Step 5 references the snapshot file and whitelist-match logic.
  - Assert `parse_files_touched` and `whitelist_match` helpers exist in `hooks/lib.sh` (or wherever shared bash lives).

### Open questions

1. **Whitelist parser robustness.** `## Files touched` is markdown — bullets with paths, sometimes with annotations. Parser must extract just paths. Architect-side discipline: paths as bare bullets, never `- src/foo.py (new)` (the `(new)` would break naive parsers unless we strip parenthetical suffixes).
2. **Globs.** If architect writes `src/auth/*.py` in `## Files touched`, expand at whitelist-build time via `compgen -G`. Disallow recursive globs (`**`) for safety.
3. **New files.** Whitelist match must accept paths that don't exist yet (architect listed them as targets). Match logic: exact-path or glob, no filesystem existence requirement.

## R5. architect state-awareness — pre-spawn fact injection

### Observation

P3 of a recent run hit `RETURN_TO_ARCHITECT` four times in a row, each time with reviewer flagging the same issue: "`## Approach` says 'add `foo()`' but `foo()` already exists in `src/auth.py:42`". Architect's re-spawn prompt carried `previous_attempt_feedback` with the reviewer's specific verdict + 6 fix-points. Sonnet architect read it, restated intent ("I will now replace instead of add"), then drafted the same `add` language in the next attempt. Same bug, same prompt, no progress.

Root cause: v0.9.3 architect persona instructs "ground claims in source" but never **mechanically guarantees** the architect saw current source state. The architect *can* Read or Grep, but the prompt doesn't force it to, and re-spawn loops show it skipping the grep when under pressure to deliver a revised plan.

### Why it's not in v0.9.3

v0.9.3 design is "advisory text + reviewer catches drift". `prior_reflections` were added in v0.9.0 as cross-phase memory — same pattern, advisory text. The pattern works when sonnet honors the rule; fails when it doesn't, and reviewer becomes the sole safety net.

The cheat-prevention pattern used elsewhere (test-hash check, reverse-prd's runtime probe → architect fact injection) hasn't been applied to `impl-architect`. R5 closes that gap.

### Proposed intervention — two-pass architect spawn

#### Pass 1 — Files touched candidate

Orchestrator spawns `impl-architect` with `pass=1`. Architect's only deliverable: a candidate file list. Return contract is strict — YAML block, no other content:

```yaml
files_touched:
  - src/auth/middleware.py
  - src/auth/handlers.py
```

Architect is forbidden from writing any other section in Pass 1. If it tries to, return contract fails, orchestrator re-asks.

#### Orchestrator — compute `<existing_code_facts>`

Between Pass 1 and Pass 2, orchestrator runs (no agent involvement):

```bash
for f in ${pass1_files[@]}; do
  echo "### $f"
  if [ -f "$f" ]; then
    echo "Recent commits:"
    git log -5 --oneline -- "$f"
    echo
    echo "Current head (first 100 lines):"
    head -100 "$f"
  else
    echo "(file does not exist yet — this is a NEW file)"
  fi
  echo "---"
done
```

Cap each file at `head -100` (or `head -50` if architect's `files_touched` is >5 entries). Token budget cap: 8K tokens. If exceeded, sort by phase-name-keyword relevance and truncate.

#### Pass 2 — Full plan

Re-spawn architect with `pass=2`. Prompt includes:

- Original Pass 1 inputs (verbatim).
- Architect's own Pass 1 `files_touched` (so it sees what facts are about).
- `<existing_code_facts>` block (the orchestrator-computed dump).

Architect drafts the five-section plan with `<existing_code_facts>` as **non-negotiable factual context**. Persona instructs: every `## Approach` step that touches a file in `files_touched` must be consistent with the facts. "add `foo()`" is invalid if `foo()` appears in `<existing_code_facts>` for that file — use "replace `foo()`" or "extend `foo()`".

### RETURN cycle — prior draft as fact

On `RETURN_TO_ARCHITECT` from any reviewer checkpoint, orchestrator extends `previous_attempt_feedback` with:

- `<previous_architect_draft>` — verbatim previous `tasks/p<n>_impl.md` content.
- `<reviewer_findings>` — verbatim reviewer issues (already today).

Currently architect *could* re-Read `tasks/p<n>_impl.md` to see its own prior draft, but the state-blind bug shows it often doesn't. Explicit injection makes the prior draft a fact, not a tool call architect might skip. Pass 1's `files_touched` is reused on re-spawn (architect picked them once; reviewer's complaint is about how, not what) — no Pass 1 re-run on RETURN.

### Implementation sketch

`commands/impl.md` Step 1 splits:

```
Step 1a — Pass 1 spawn:
  > impl-architect mode=pass1
  > Output ONLY a YAML files_touched list.
  > Do NOT draft any other section.

Step 1b — Compute facts:
  EXISTING_FACTS=$(compute_existing_code_facts "${pass1_files}")

Step 1c — Pass 2 spawn:
  > impl-architect mode=pass2
  > files_touched (from Pass 1): ...
  > existing_code_facts: ${EXISTING_FACTS}
  > Draft the full five-section plan per agent definition.
```

`agents/impl-architect.md` gets a new `## Pass discipline (two-pass spawn)` section:

- Pass 1 contract: YAML-only output, no other content. If you draft sections in Pass 1, the orchestrator will reject and retry.
- Pass 2 contract: `<existing_code_facts>` is factual context. Any `## Approach` statement contradicting it is a defect, not a stylistic choice.
- Re-spawn: `<previous_architect_draft>` is what you just wrote and got rejected. Use `<reviewer_findings>` to revise.

### Tests

- `tests/test_agent_impl_architect.sh` extended:
  - Assert `## Pass discipline (two-pass spawn)` section heading exists.
  - Assert Pass 1 YAML-only contract + Pass 2 facts-are-load-bearing rule appear verbatim.
- `tests/test_command_impl.sh` extended (or new):
  - Assert two-architect-spawn flow in Step 1.
  - Assert `compute_existing_code_facts` helper exists in `hooks/lib.sh`.
  - Assert `<previous_architect_draft>` injection on RETURN.

### Open questions

1. **Token cost.** Pass 2 carries Pass 1 prompt + facts block (~8K cap). Double spawn on every phase ≈ +30% token usage per phase. Worth it vs current reviewer-retry cost (each RETURN re-spawns architect anyway). Net: probably neutral or savings if R5 cuts RETURN frequency.
2. **Pass 1 hallucination.** If Pass 1 returns files not in PRD scope, Pass 2 carries wrong facts. Add Pass 1 sanity check: every file must either exist OR have a path matching the module's directory structure. Soft warn, don't block.
3. **Cascading RETURN.** Review #2 RETURN_TO_ARCHITECT cascades from checkpoint #2. Reuse Pass 1's `files_touched`? Yes — Pass 1 invariant within a phase.
4. **First-phase boostrap.** No prior commits in a fresh module. `git log -5` returns empty. Facts block says "(no prior commits — fresh file)" → architect treats as add-from-scratch. No special case needed.

## R6. findings.md reflections — per-entry metadata + cross-update injection

### Observation

v0.9.3 limits `prior_reflections` to the **same update's** `findings.md`. Reflections die at update close. Real-world: a lesson from update A (e.g., "always grep before claiming 'add'") generalizes to update B's same module. Currently that lesson evaporates.

### Why it's not in v0.9.3

CLAUDE.md explicit defer: "cross-update reflections deferred". The current update-scoped design was the minimum viable shape; cross-update retrieval needs a filter mechanism to avoid context bloat.

### Proposed intervention

#### Per-entry metadata + heading rename

Each `### <heading>` entry in `## Reflections` gains a `<!-- meta: ... -->` block immediately after the heading:

```markdown
## Reflections

### 2026-05-11-runtime-probe/p3: cross-validation
<!-- meta:
  files_touched: [scripts/probe-runtime.sh, hooks/lib.sh]
  keywords: [git-add, working-tree, commit-hygiene]
  trigger: reviewer-RETURN
  retries: 2
  created: 2026-05-11
-->

- Misstep: ...
- Root cause: ...
- **Heuristic:** ...
```

**Heading format change**: `### Phase <n>: <name>` → `### <update-slug>/p<n>: <name>`. Update-slug is the parent directory name (`2026-05-11-runtime-probe`). When cross-update injection happens, the heading itself carries provenance — architect sees "this is from a different update".

`templates/findings.md` and `agents/impl-architect.md` ` Inputs` section both update to reflect the new heading shape.

#### Cross-update injection at architect spawn

In `commands/impl.md` Step 1 (Pass 1 and Pass 2 both, with different filters):

```bash
# Walk every findings.md in this module (immutable historical record)
FINDINGS_FILES=$(find docs/super-manus/impl/${MODULE}/*/findings.md)
# Parse each ### entry with <!-- meta: ... --> block
# Filter:
#   Pass 1: keywords ∩ phase_name_tokens ≠ ∅                       (no files_touched yet)
#   Pass 2: (files_touched ∩ pass1_files ≠ ∅)                       (stronger signal)
#           OR (keywords ∩ phase_name_tokens ≠ ∅)
# Sort: file mtime DESC (newer first), retries DESC (high-retry = stronger lesson)
# Cap: K=5 entries, total ≤4K tokens
# Inject as <prior_lessons> fact block
```

Same-update reflections (current `prior_reflections`) are still included — they're a subset of this glob. R6 generalizes the same mechanism across updates.

#### User-curated entries

User-curated lessons (e.g., "super-manus bug: code-writer must `git status` before commit") go into the **active update's** `findings.md ## Reflections` with `trigger: user-curated`. Mechanism:

- `/super-manus:log` extends to accept a `--reflection` flag that prompts for keywords + body and writes the entry.
- Orchestrator persona heuristic: when user message contains "记到 reflection" / "save as reflection" / "this is a lesson" / similar intent, surface `AskUserQuestion` offering to write the entry.

### Legacy heading migration

Old reflections use `### Phase <n>: <name>`. On parse:

- If heading matches `### Phase \d+:`, derive update-slug from parent directory path.
- Architects can still consume legacy-format entries (parser handles both).
- No bulk rename. Old entries keep their headings; new entries use the new format.

### Tests

- `tests/test_template_findings.sh` extended:
  - Assert `## Reflections` section description mentions the metadata block format.
  - Assert the new heading shape `<update-slug>/p<n>` appears in template example.
- `tests/test_command_impl.sh` extended:
  - Assert cross-update findings glob + filter logic appears in `commands/impl.md` Step 1.
  - Assert `parse_reflection_meta` helper exists in `hooks/lib.sh`.
- `tests/test_agent_impl_architect.sh` extended:
  - Assert `Inputs` section's `prior_reflections` paragraph describes the new heading format.

### Open questions

1. **Stale signal.** Reflections >6 months old may reference removed code. Inject with `(stale, audit)` decoration vs skip entirely? Recommend decoration over skip — let architect judge. Threshold configurable via `.super-manus/agents.yml`; default 6 months.
2. **Top-K cap.** K=5 with secondary sort by `retries:` DESC (high-retry = stronger lesson). 50+ historical updates filtered to ~5 is reasonable.
3. **Keyword schema.** Free-text `keywords:` array, no controlled vocabulary. Soft retrieval (substring match on heading tokens ∪ keywords). No NLP embeddings — keep it grep-able.
4. **Module-only scope.** Cross-update injection stays within a single module (`docs/super-manus/impl/${MODULE}/*`). Cross-module lessons are typically too noisy. Could relax later.

## Cross-cutting open questions

1. **R5 + R6 interaction.** R5's two-pass means R6's injection runs twice (Pass 1: keyword-only filter; Pass 2: full filter). Wasteful? Probably not — Pass 1 injection is small (no files_touched filter). Pass 2 is the load-bearing one. Keep both for safety.

2. **R4 + R5 + R6 ship together vs piecemeal?** Independent code paths:
   - **R4** (lowest risk, mechanical, fixes a concrete bug) — ship first.
   - **R5** (largest blast radius — changes every architect spawn) — ship second, after R4 stable.
   - **R6** (depends on R5's facts pattern being battle-tested) — ship third.
   - All three together = v0.9.4. Piecemeal = v0.9.4 (R4) / v0.9.5 (R5) / v0.9.6 (R6).

3. **Reviewer impact.** R5's two-pass + RETURN-cycle prior-draft injection should reduce reviewer RETURN frequency on `impl-architect`. If telemetry confirms this after R5 ships, the retry budget (currently 2 RETURNs before ESCALATE) could be tightened to 1 — the reviewer becomes a sanity check, not a safety net.

## Status

NOT yet ratified. Each R-item needs explicit user "ship it" before implementation. Recommended sequence: R4 → R5 → R6, separate milestones, separate phase plans, separate releases.
