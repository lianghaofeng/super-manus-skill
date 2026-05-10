<!-- Append-only. Keep entries TIGHT. -->
<!-- Decisions: 2-3 lines max each — what was chosen / why / what was ruled out. NO code, file paths, function names, line numbers, or implementation steps (those live in tasks/p<n>_impl.md and commit messages). -->
<!-- Errors: one row per failure; Resolution column is one short sentence. -->
<!-- Data points: smoke numbers, eval scores, links — bullet form, no narrative. -->
<!-- Reflections: written ONLY by the /super-manus:impl orchestrator at phase close. One H3 entry per phase that had ≥1 reviewer RETURN event. The Heuristic line is the load-bearing one — it's what next phase's impl-architect honors. Do NOT write here by hand.
v0.9.4 R6: each entry gains a <!-- meta: ... --> block (files_touched / keywords / trigger / retries / created) and the H3 heading is `### <update-slug>/p<n>: <name>` (was `### Phase <n>: <name>` pre-v0.9.4). The orchestrator filters cross-update reflections at architect spawn — only matching entries get injected. -->
# Findings: <feature title>

## Decisions

(no decisions logged yet)

<!-- Format per entry:
### YYYY-MM-DD: <one-line topic>
- Chose: <one sentence>
- Why: <one sentence>
- Ruled out: <one sentence, optional>
-->

## Errors

| When | What failed | Resolution |
|---|---|---|

## Data points / research

(no data points yet)

## Reflections

(no reflections yet)

<!-- Format per entry, written at phase close by /super-manus:impl after review #3 APPROVE.
     Skip the entry entirely if the phase had zero reviewer RETURN events.
### <update-slug>/p<n>: <name>
<!-- meta:
  files_touched: [path/a.py, path/b.py]
  keywords: [token1, token2, token3]
  trigger: reviewer-RETURN
  retries: <N>
  created: <YYYY-MM-DD>
-->
- Misstep: <one sentence — what attempt 1 got wrong; the surface event>
- Root cause: <one sentence — why the writer made that choice>
- Heuristic: <one sentence — rule for next phase to avoid this>

v0.9.4 R6 metadata fields (orchestrator-filled at write time):
  - files_touched: array of paths from ## Files touched (sm_parse_files_touched)
  - keywords: lowercase alnum tokens from phase_name (default; orchestrator may add domain terms)
  - trigger: always `reviewer-RETURN` (auto-write) or `user-curated` (manual via /super-manus:log)
  - retries: count of `phase p<n>` rows in ## Errors for this phase
  - created: today's date (orchestrator)

The Reflexion-style cross-phase memory section is now cross-UPDATE too: the
orchestrator at the next architect spawn globs every findings.md under
docs/super-manus/impl/<module>/*/, filters by keyword/files match, and injects
the top-K matches as <prior_lessons> fact block. Legacy `### Phase <n>:`
entries (pre-v0.9.4) are still parsed; their <update-slug>/ prefix is added at
injection time. -->

