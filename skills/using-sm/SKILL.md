---
name: using-sm
description: How to read and write super-manus state files (task_plan.md, findings.md, progress.md, tasks/p<n>_impl.md). Triggered by /super-manus:* slash commands and SessionStart/Stop/PostToolUse hook reminders in super-manus-enabled projects.
user-invocable: false
---

# using-sm

The super-manus plugin keeps a small set of persistent files per feature so state survives `/clear`, `/compact`, and full session boundaries. This skill teaches you the read/write protocol. Follow it whenever a `/super-manus:*` command runs or a hook reminder references "the using-sm skill conventions".

User-facing commands (all in the `/super-manus:` namespace):

- `/super-manus:start <name>` — create a new feature folder + activate it
- `/super-manus:switch <name>` — switch to an existing feature
- `/super-manus:catchup` — re-inject the active plan into context mid-session
- `/super-manus:phase <n>` — open or seed the per-phase implementation plan `tasks/p<n>_impl.md`
- `/super-manus:log` — write a `## Session log` entry on demand (no LLM judgment, force-write)

## 1. Where state lives

```
<project-root>/
├── .super-manus/
│   └── active                                  # text file: current feature folder name
└── docs/super-manus/
    └── <YYYY-MM-DD>-<feature-name>/
        ├── task_plan.md                        # goal + phases index (LLM-maintained, no code)
        ├── findings.md                         # decisions / errors / research (LLM-maintained)
        ├── progress.md                         # commit log + session log (hook-managed; do not hand-edit)
        └── tasks/
            └── p<n>_impl.md                         # per-phase implementation plan, lazy-created by /super-manus:phase <n>
```

`.super-manus/active` contains just the folder basename (e.g. `2026-05-04-refactor-auth`). Switch features with `/super-manus:switch`; create new ones with `/super-manus:start`. Always resolve the active feature folder by reading `.super-manus/active` first — never hard-code a path.

## 2. What goes in which file

**`task_plan.md`** — the spine.
- `## Goal`: one paragraph, immutable across the feature lifetime.
- `## Phases`: markdown table with columns `# | Name | Status | Notes`.
- Status values: `pending` / `in_progress` / `blocked` / `closed` (lowercase, exact). The `## Outstanding` section in `progress.md` is regenerated from this table by parsing those exact strings — typos break the regen.
- **Not for**: code blocks, pseudo-code, file diffs, or multi-line implementation sketches. The `Notes` column is strictly one line. Anything bigger goes in `tasks/p<n>_impl.md` (per-phase plan; see the `tasks/p<n>_impl.md` entry below) or `findings.md ## Data points / research`.

**`findings.md`** — your working memory on disk.
- `## Decisions`: dated entries — what was chosen, why, what alternatives were ruled out.
- `## Errors`: table with columns `When | What failed | Resolution`.
- `## Data points / research`: free-form — smoke results, screenshots-as-text, eval numbers, links.

**`progress.md`** — auto-managed; treat as read-only by default.
- `## Completed commits`: the post-commit hook appends one line per `git commit` (Bash-tool calls only — external terminal commits aren't seen).
- `## Session log`: the Stop hook surfaces a checkpoint **every N turns OR when there are commits since the latest entry** (whichever fires first; default `N=5`, modes via `SUPER_MANUS_LOG_MODE`). When surfaced, you **judge** whether the activity warrants a new line — skip if not. `/super-manus:log` force-writes one immediately.
- `## Outstanding`: regenerated from `task_plan.md` by `scripts/refresh-outstanding.sh` — never edit by hand.

**`tasks/p<n>_impl.md`** — per-phase implementation plan (one file per phase, lazy).
- Created by `/super-manus:phase <n>` when the active phase needs more than a one-line note. Trivial phases don't need one.
- Sections: `## Objective` (what "done" means), `## Approach` (the chosen route — code, pseudo-code, file diffs all live here), `## Files touched` (one-line reasons), `## Verification` (how you'll know it's closed). Headings are stable.
- Lifecycle: fill `## Objective` first, evolve `## Approach` in place, leave the file as historical record when the phase closes. Don't delete; future sessions reconstruct intent from it.
- Optionally, `task_plan.md`'s `Notes` column can carry a relative link like `tasks/p1_impl.md` to point at the plan, but it's not required.

## 3. When to update each file

| File | Trigger |
|---|---|
| `task_plan.md` | A phase status changes (closed / in_progress / blocked); a new phase is added or split. |
| `findings.md` | Any decision (with reasoning), any error encountered, any research finding worth surviving the session. |
| `progress.md` | NEVER directly. Wait for a hook reminder, or be invoked via `/super-manus:log`. The PostToolUse (post-commit) hook will tell you to write to `## Completed commits`; the Stop hook checkpoint asks you to consider writing to `## Session log` (your call to skip if nothing log-worthy happened). |
| `tasks/p<n>_impl.md` | A phase entered `in_progress` and is non-trivial; the approach changes mid-phase; the verification step changes. |

## 4. The 2-action rule

After every 2 view/search/grep operations, write the key findings to `findings.md` before they fall out of context. Borrowed from [planning-with-files](https://github.com/OthmanAdi/planning-with-files): treat the file as RAM-extension. If you found something worth knowing again, write it down — don't trust your context window. Be aggressive about externalizing; the cost of an extra Edit is trivial compared to the cost of re-deriving a finding after `/compact`.

## 5. The 3-strike error protocol

When something fails (test, command, tool call):

- **Strike 1** — log to `findings.md ## Errors` table: `When | What failed | what you tried`.
- **Strike 2** (same error class, second time) — log AND mutate your approach. Try a different angle. Don't grind on the same fix.
- **Strike 3** (same error class, third time) — log AND stop. Escalate to the user with a summary of what you've tried, what you suspect, and what would unblock you.

The point is to surface tarpits early, not to slog through them in silence.

## 6. Anti-patterns

- Using TodoWrite for cross-session persistence — TodoWrite resets on `/clear`. Use `task_plan.md ## Phases` instead.
- Writing to `progress.md` without a hook reminder — you'll race with the auto-managed sections and produce duplicate or out-of-order entries.
- Putting errors in `task_plan.md` — they belong in `findings.md ## Errors`.
- Pasting code, pseudo-code, file diffs, or multi-line implementation sketches into `task_plan.md` — the file is a phase index, not a scratchpad. Use `tasks/p<n>_impl.md` for the active phase (run `/super-manus:phase <n>`) or `findings.md ## Data points / research`.
- Reordering or renaming the schema headings — hooks parse by heading name (`## Phases`, `## Outstanding`, `## Completed commits`, `## Session log`) and will silently produce wrong output if you rename them.
- Creating ad-hoc files (`notes.md`, `decisions.md`, `todo.md`) inside the feature folder — keep state in the canonical files.
- Hand-editing `## Outstanding` in `progress.md` — `scripts/refresh-outstanding.sh` will overwrite it on the next refresh.

---

*The 2-action rule and 3-strike error protocol are borrowed from [planning-with-files](https://github.com/OthmanAdi/planning-with-files).*
