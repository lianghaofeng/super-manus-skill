---
description: Standalone wiki health pass — scan docs/super-manus/wiki/ for contradictions, stale references, orphans, gaps, and broken cross-refs. Non-blocking; appends a lint entry to wiki/_log.md for user review. Same scan that runs as the end-of-update drift gate's Pass 4, but invokable on demand (e.g. monthly maintenance, after a large PRD edit, or before a release).
---

This is the v0.9.8 R19 standalone invocation of the wiki-lint pass. Spawns `impl-reviewer` in `mode=wiki-lint`, lets it run the five health checks against `docs/super-manus/wiki/` and `docs/super-manus/impl/*/*/findings.md`, and surfaces the result to the user. **Non-blocking by design** — wiki rot is a long-term failure mode the user should see, but it should never gate a milestone or PR.

The same wiki-lint pass also runs automatically as Pass 4 of the end-of-update drift gate (see `/super-manus:impl` and `/super-manus:impl-all`). This command exists for the off-milestone case: scheduled maintenance, post-PRD-edit sanity check, pre-release wiki health audit.

## Preconditions

If `docs/super-manus/prd/` is not a directory, the project is not super-manus-enabled — tell the user to run `/super-manus:start` first; stop.

If `docs/super-manus/wiki/` is absent (pre-v0.9.8 project, or fresh project that hasn't accumulated a wiki yet), tell the user:

> No wiki/ directory at `docs/super-manus/wiki/` — either this project hasn't been re-`/super-manus:start`-ed since v0.9.8 (re-run is idempotent and will seed the skeleton), or no rules have been promoted yet (run `/super-manus:impl` through one or more phases; at pre-close the reviewer may flag wiki-candidates which become the first topic-file content).

then stop.

## Spawn the reviewer in wiki-lint mode

Per-agent model override resolution applies (same pattern as `/super-manus:impl`):

```bash
source "${CLAUDE_PLUGIN_ROOT}/hooks/lib.sh"
override=$(sm_agent_model impl-reviewer)
```

If `$override` is non-empty (`opus` / `sonnet` / `haiku`), pass `model: "$override"` to the Agent tool. Otherwise omit and the agent's frontmatter pin (`model: opus`) applies.

Spawn `impl-reviewer` (Agent tool, `subagent_type="super-manus:impl-reviewer"`) with the wiki-lint-specific input set:

- `mode` — `wiki-lint`
- `wiki_dir` — `docs/super-manus/wiki/` absolute path
- `findings_root` — `docs/super-manus/impl` absolute path (the reviewer globs `*/*/findings.md` under this root for gap detection)
- `project_root` — current working directory absolute path

Do NOT pass `phase_number` / `phase_name` / `phase_plan_path` / `task_plan_path` / `wiki` block — those are impl-mode inputs. The wiki-lint mode reads `wiki/` directly via its read tools.

Spawning prompt skeleton:

> Inputs from /super-manus:wiki-lint orchestrator (standalone invocation):
>
> - mode: `wiki-lint`
> - wiki_dir: `<absolute path>`
> - findings_root: `<absolute path>`
> - project_root: `<absolute path>`
>
> Run wiki-lint per your agent definition's `### Mode \`wiki-lint\`` section. Run all five checks (contradiction / stale / orphan / gap / cross-ref miss), append one `## [<today>] lint | standalone` H2 entry to `wiki/_log.md` summarizing the findings, and return a `WIKI_LINT_COMPLETE` verdict with the five counts.

## Surface to the user

When the reviewer returns the `WIKI_LINT_COMPLETE` verdict, parse the counts and tell the user verbatim what landed in `wiki/_log.md`:

> Wiki lint complete. Findings appended to `docs/super-manus/wiki/_log.md` as one new `## [<today>] lint | standalone` entry. Summary:
>
> - Contradictions: `<N>` (rule pairs making incompatible claims)
> - Stale: `<N>` (rules referencing files / symbols / packages no longer in source)
> - Orphan: `<N>` (rules promoted >6 months ago that no findings.md has ever cited)
> - Gap: `<N>` (recurring missteps in ≥3 updates' findings with no covering wiki rule)
> - Cross-ref miss: `<N>` (broken `[[other-rule]]` or `wiki/<other>.md#anchor` links)
>
> Read the full report at `docs/super-manus/wiki/_log.md` (look for the most recent `## [<today>] lint` entry). Resolution path: edit `wiki/<topic>.md` files directly (retire orphans, fix contradictions, add missing cross-refs); for Gaps, trigger a `wiki-candidates:` flag on the next relevant phase's reviewer pre-close (or write the rule manually). There is no auto-fix — wiki maintenance is human-curated.

If all five counts are zero, the friendlier summary:

> Wiki lint complete. Zero findings across all five checks — wiki is healthy. Entry appended to `docs/super-manus/wiki/_log.md`.

## When the reviewer fails to write the log entry

If the reviewer returns `WIKI_LINT_COMPLETE` but no new entry was appended to `wiki/_log.md` (verify by reading the file before and after the spawn), the wiki-lint mode contract was violated. Append one row to `docs/super-manus/drift_log.md ## PRD drift` flagging the reviewer-side bug (this is the only path where wiki-lint findings escalate to a drift row — every other failure is non-blocking):

```
| <YYYY-MM-DD> | <author> | wiki | reviewer wiki-lint mode failed to append _log.md entry | pending |
```

Then surface to the user with the verdict text verbatim so they can investigate. Do NOT retry automatically.

## Frequency

This command is intended for **on-demand** invocation. Suggested cadence:

- Monthly, as scheduled maintenance.
- After a large PRD or spec edit (potentially invalidates wiki rules).
- Before cutting a release (wiki health is part of release readiness).
- When `/super-manus:impl-all`'s end-of-update Pass 4 surfaced a high count and you want to re-scan after manual edits.

No locking, no rate limit — wiki-lint is a read-only-ish operation (one Write to append `_log.md`), safe to invoke repeatedly. Each run produces an independent entry, so chronological history is preserved in `_log.md`.
