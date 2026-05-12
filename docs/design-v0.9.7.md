# super-manus v0.9.7 — multi-author baseline (P0-P2)

**Status: ratified AND implemented in v0.9.7.** Three R-items shipped together — all
additive on top of v0.9.6; no breaking changes, no command renames, one schema migration
(`drift_log.md` 4 → 5 columns) handled automatically by `scripts/sm-start.sh` for
pre-v0.9.7 projects.

`plugin.json` bumped from `0.9.6` to `0.9.7` on this release.

## Context: the "we want to run multiple Claude Code instances" gap

After v0.9.6 dogfooding, three concrete multi-author friction points surfaced. None of
them block single-user work (so v0.9.6 was correct to ship without them), but each
recurs the moment a second author starts touching the same project:

1. **`drift_log.md` and `roadmap.md` merge conflicts on every parallel commit.** Both
   are append-only ledgers. Two authors on two branches each appending a new row at
   the file's last line will collide at git merge time — same line, two replacements
   of the trailing newline. The conflict is trivial to resolve (keep both rows), but
   it triggers on every concurrent commit, so the cumulative review-friction cost is
   high. The fix is git-native (`merge=union` per `.gitattributes`), not a super-manus
   primitive.
2. **No path-based reviewer routing for module ownership.** A teammate touches
   `docs/super-manus/prd/api.md` and `docs/super-manus/impl/api/...` but the PR sits
   waiting for whoever the author manually picks as reviewer — the actual `api`
   module owners aren't auto-assigned. GitHub solves this with `CODEOWNERS`; super-manus
   should ship a ready-to-adapt template so users don't have to derive the correct
   per-module path globs themselves.
3. **`drift_log.md` rows carry no author attribution.** PR reviewers ask "who added
   this row, and was the resolution-cell flip them or me?" There is no field. `git
   blame` works but is one extra step; for a multi-author ledger the column should
   be inline.

All three are addressable by **adding** files / columns — none requires changing how
existing commands behave for single-user projects. v0.9.7 ships the minimal three-piece
"multi-author baseline" so 2-10 person teams can collaborate without the cumulative
merge-friction cost.

## R13. `.gitattributes` `merge=union` for append-only ledgers

### Observation

`drift_log.md` and `roadmap.md` are the only two project-state files that grow by
append (new drift row / new update history entry) rather than by structural edit.
git's default 3-way merge treats every append as a same-line conflict whenever two
branches both append. `merge=union` is git's built-in strategy for exactly this case:
both branches' added lines are preserved, no conflict marker is written.

### Why not blanket-apply union to all super-manus files

PRD (`prd/<module>.md`) and spec (`prd/<module>.spec.md`) files are **structured
documents**, not append-only ledgers. Two authors changing the same `## Quality bar`
sentence — Alice "200ms p95" → "100ms p95"; Bob "200ms p95" → "300ms p95" — should
produce a git conflict so a human picks the correct value. `merge=union` on these
files would silently keep BOTH lines, producing a self-contradictory PRD with no
conflict marker. That's a worse failure than today's merge friction.

So the rule is **narrow**: `merge=union` only on the two append-only ledgers. PRD and
spec files continue to use git's default 3-way merge, which surfaces real conflicts.
A future v0.11 may add a section-aware merge driver for PRD/spec — that's out of
scope for v0.9.7.

### Shipped shape

`.gitattributes` at the plugin root:

```
docs/super-manus/drift_log.md merge=union
docs/super-manus/roadmap.md merge=union
```

Two lines. No PRD paths. No spec paths.

The file is committed to the **plugin** repo (so the rule rides along with the
plugin) AND seeded into target projects by `/super-manus:start` if their repo root
has no `.gitattributes` of its own. Projects that already have a `.gitattributes`
get a heads-up message instead of a silent overwrite — they can copy the two lines
themselves.

### Tests

- `tests/test_gitattributes.sh` (new) — asserts file exists, contains both ledger
  rules, contains NEITHER `prd/*.md` NOR `prd/*.spec.md` (negative regression: a
  future contributor must not "fix" perceived PRD merge friction by adding union
  there).

## R14. `templates/codeowners.example` — adaptable per-module routing

### Observation

Every super-manus project has the same module-shape layout
(`prd/<module>.md` + `prd/<module>.spec.md` + `impl/<module>/...`), so the
CODEOWNERS rules that GitHub needs are mechanically derivable per module. Asking
each user to figure out the right globs is needless friction; shipping a template
that explicitly maps super-manus paths → reviewer roles solves it once.

### Why a template, not an auto-generator

A real `.github/CODEOWNERS` requires the user's actual GitHub team / org / username
strings, which the plugin doesn't know. An auto-generator that tried to infer
"backend-team" from a module named "api" would guess wrong half the time and lock
users into renames they can't undo. A template the user copies and edits is the
clean ROI choice: 1 hour of plugin work, 5 minutes of user adaptation per project.

### Shipped shape

`templates/codeowners.example` — a heavily commented example file with three
sections:

1. **Per-module ownership block** — one stanza per example module showing the three
   path patterns each module needs (`prd/<module>.*` + `prd/<module>.spec.*` +
   `impl/<module>/**`).
2. **Cross-module shared files** — `_index.md`, `roadmap.md`, `drift_log.md` require
   multiple teams' approval (any cross-module change touches them).
3. **GitHub CODEOWNERS quirks block** — gitignore-style path matching (not glob),
   same-org-only teams, last-match-wins, file size limits. These are the four
   sharp edges that bite new users; calling them out inline saves a debugging
   session.

The template is **NOT** auto-installed by `/super-manus:start` (would conflict with
projects that already have CODEOWNERS rules for non-super-manus paths). Users copy
it manually:

```bash
cp ${CLAUDE_PLUGIN_ROOT}/templates/codeowners.example .github/CODEOWNERS
# then edit @your-org/<team> placeholders
```

The README's "Multi-author setup" section references it; `commands/start.md` adds
a one-line mention.

### Tests

- `tests/test_template_codeowners.sh` (new) — asserts file exists, has the three
  required sections (per-module / cross-module / quirks), demonstrates the three
  required path patterns per module, calls out at least 3 of the GitHub-specific
  quirks (gitignore-style matching, last-match-wins, same-org teams).

## R15. `drift_log.md` Author column (4 → 5)

### Observation

Every drift row's audit story has three questions: when (Date), what (Conflict),
how-resolved (Resolution). For single-user projects, "who" is implicit. For
multi-author projects, "who appended this row" and (separately) "who flipped this
row's Resolution from pending to absorbed" are routine PR-review questions. `git
blame docs/super-manus/drift_log.md` answers them, but the trip out of the file is
friction; the column is cheap to add and always-correct (sourced from
`git config user.name` at append time).

### Why one column, not two

Considered: separate `Author` (append) and `Resolved by` (flip) columns. Decided
against — the second column is only filled on rows that have been resolved, which
muddles the schema. The append-only ledger model is "row's primary author is the
appender; Resolution-cell mutations are visible in `git log -p` if anyone cares".
One Author column matches the existing single-author append-only model with
minimum disruption.

### Why between Date and Module (not at the end)

Placing Author between Date and Module groups the "context" columns (when, who,
what-module) before the "content" columns (conflict, resolution). Readers scan
left-to-right; the natural reading flow is "on date D, author A noted module M
had conflict C, resolved as R". Putting Author last buries it after the longest
free-text columns where it's easy to miss.

### Shipped shape

#### Schema

```
| Date | Author | Module | Conflict | Resolution |
| --- | --- | --- | --- | --- |
```

In both H2 sections (`## PRD drift` and `## Spec drift`) of `drift_log.md`.

#### Author value sourcing

At every row-append site, the Author cell is filled from `git config user.name`:

```bash
AUTHOR=$(git config user.name 2>/dev/null || echo "unknown")
```

Empty / unset config falls back to `unknown`. This keeps the column always present;
PR review sees `unknown` rows as a signal that the appender hadn't configured git
identity yet.

#### Row-append sites updated

All of these go from 4 cells to 5 cells (Author second):

- `commands/impl.md` — per-phase drift check, test-writer pipeline violation,
  code-writer hash tamper, end-of-update PRD declared/implemented mismatch,
  missing-spec.md detection (Pass 1).
- `commands/drive.md` — commit-hint drift sweep.
- `commands/impl-all.md` — references impl.md procedures (no row-append site of
  its own).
- `commands/prd-update.md` R11 logging branches (b / c / a→ii / a→iv).
- `commands/spec-update.md` R11 logging branches symmetric.

The Conflict column format and Resolution semantics are unchanged.

#### Migration for pre-v0.9.7 projects

`scripts/sm-start.sh` adds a migration block that runs on every invocation (before
the idempotent short-circuit), like the v0.9.5 R10 `prd_drift.md → drift_log.md`
migration:

1. Detect: `drift_log.md` exists AND its `## PRD drift` (or `## Spec drift`) header
   row is the 4-column form `| Date | Module | Conflict | Resolution |`.
2. Rewrite each section's header + separator to 5 columns:
   `| Date | Author | Module | Conflict | Resolution |` plus matching separator.
3. Inject `unknown` as the second cell of every existing data row.
4. Idempotent: a second invocation finds 5 columns and short-circuits.

The migration is destructive on the affected file (in-place rewrite), but the
result is forward-compatible — old rows stay readable, new rows have proper Author
attribution. No `.legacy` backup file is created (unlike R10's prd_drift migration)
because the change is purely additive; rollback to 4 columns is `git revert` away.

### Tests

- `tests/test_template_drift_log.sh` — extended: 5-column header expected (with
  Author second), both H2 sections still get the schema, header-comment text
  unchanged.
- `tests/test_command_prd_update_logic.sh` — extended: R11 logging table examples
  show 5-column rows.
- `tests/test_command_spec_update_logic.sh` — extended: R11 logging table examples
  show 5-column rows.
- `tests/test_command_impl_logic.sh` — extended: each row-append site documents
  5-column form including `git config user.name` source.
- `tests/test_command_drive_logic.sh` — extended: drift-sweep row example is 5
  columns.
- `tests/test_script_sm_start_migrate_author.sh` (new) — feeds a synthetic 4-column
  drift_log to a sandboxed sm-start.sh invocation, asserts the file ends up
  5-column with `unknown` injected, second invocation is a no-op.

## Cross-cutting concerns

1. **R13 + R14 + R15 are independent.** R13 touches only `.gitattributes` and its
   test. R14 touches only `templates/codeowners.example` and its test. R15 touches
   the drift_log template + 5 command files + migration script + 6 test files.
   Either of the three could ship alone if a future R-item reorders priority.

2. **No agent behavior changes.** Agents don't read or write `drift_log.md` directly
   (the orchestrator does); they don't depend on `.gitattributes` (git does). R14
   is documentation-shaped. None of the four pipeline agents
   (architect / test-writer / code-writer / reviewer) needs a persona update.

3. **No new helper functions.** `git config user.name` is inlined at each append
   site rather than wrapped in a `sm_author` helper — six call sites, two-line
   inline pattern, helper would be premature abstraction. If the lookup logic
   grows (e.g., GitHub-username resolution from git remote), revisit then.

4. **Migration is idempotent.** Like the v0.9.5 R10 prd_drift→drift_log migration,
   the R15 author-column migration runs before sm-start.sh's idempotent short-
   circuit. A second invocation in a 5-column project finds the new schema present
   and exits the migration block without modifying anything.

5. **`merge=union` is git-native.** No super-manus code reads or enforces the
   `.gitattributes` rule — git's own merge driver picks it up. The plugin's
   responsibility is shipping the file + the test that asserts its contents stay
   correct over time.

## Open questions (deferred)

1. **Should `.gitattributes` also seed into target projects by `/super-manus:start`?**
   Currently it sits at the plugin repo root only — projects benefit from it when
   editing the plugin itself, but a fresh super-manus-using project still gets git
   default merge for its `docs/super-manus/drift_log.md`. Adding it to sm-start.sh's
   seeding logic (with the "don't overwrite existing .gitattributes" guard) would
   close that gap. Defer — first see if users hit the merge friction in their own
   projects, which forces the conversation.

2. **CODEOWNERS auto-installation hook.** A future variant could probe for `.github/`
   in the project root, detect "no CODEOWNERS yet", and offer (via `AskUserQuestion`)
   to seed a minimal version from the template with the user's git remote
   organization auto-detected. Defer — the manual copy is documented and
   adapt-once-then-forget; auto-installation is a larger UX surface to design.

3. **`Resolved by` column.** As above, only filled on resolved rows. Defer until a
   user reports the audit gap in practice.

4. **GitHub username vs git author name.** `git config user.name` is what we use;
   in some teams the GitHub username (`gh api user` or parsed from the remote)
   would be more useful for cross-referencing with CODEOWNERS. Defer — the
   value-add is small versus the surface-area increase (new dependency on `gh`
   CLI / remote-parsing).

## Status

**Design ratified AND implemented in v0.9.7 (single-shot release).** Three R-items
shipped together — see `plugin.json` version `0.9.7` and the matching test extensions.

What landed:

- **R13** — `.gitattributes` at plugin root with two `merge=union` rules for the
  append-only ledgers (`drift_log.md` + `roadmap.md`). PRD/spec files deliberately
  excluded; future v0.11 may add a section-aware merge driver for those.

- **R14** — `templates/codeowners.example` with per-module / cross-module / quirks
  sections. Manually copied by users; not auto-installed.

- **R15** — `drift_log.md` schema goes 4 → 5 columns; Author cell inserted between
  Date and Module; populated by `git config user.name` at every append site;
  pre-v0.9.7 projects auto-migrated by sm-start.sh.

Ratified design decisions:

- **R13** — narrow scope (ledgers only, not PRD/spec) to prevent silent merge of
  contradictory PRD edits.
- **R14** — template, not auto-generator; manual copy is the right ROI today.
- **R15** — single Author column (not Author + Resolved-by); inserted between Date
  and Module (not appended); sourced from `git config user.name` (not GitHub
  username).

Not in scope (deferred to future R-items if real-world data shows need):

- `.gitattributes` seeded into target projects by sm-start.sh (R13 OQ1)
- CODEOWNERS auto-installation hook (R14 OQ2)
- `Resolved by` column on drift_log rows (R15 OQ3)
- GitHub username resolution for Author column (R15 OQ4)
- Section-aware merge driver for PRD/spec (v0.11 candidate)
- In-flight marker `prd/_index.md ## In-flight updates` (v0.10 R3 candidate, deferred
  for separate design)
- Per-team workspace split (model B from the multi-author discussion; v1.0 candidate)
