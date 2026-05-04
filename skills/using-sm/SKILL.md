---
name: using-sm
description: How to read and write super-manus state files (task_plan.md, findings.md, progress.md). Triggered by /sm slash commands and SessionStart/Stop/PostToolUse hook reminders in super-manus-enabled projects.
user-invocable: false
---

# using-sm

The super-manus plugin keeps three persistent files per feature so state survives `/clear`, `/compact`, and full session boundaries. This skill teaches you the read/write protocol. Follow it whenever a `/sm` command runs or a hook reminder references "the using-sm skill conventions".

## 1. Where state lives

```
<project-root>/
├── .super-manus/
│   └── active                                  # text file: current feature folder name
└── docs/super-manus/
    └── <YYYY-MM-DD>-<feature-name>/
        ├── task_plan.md                        # goal + phases (LLM-maintained)
        ├── findings.md                         # decisions / errors / research (LLM-maintained)
        ├── progress.md                         # commit log + session log (hook-managed; do not hand-edit)
        └── tasks/                              # reserved for v0.2; empty in v0.1
```

`.super-manus/active` contains just the folder basename (e.g. `2026-05-04-refactor-auth`). Switch features with `/sm switch`; create new ones with `/sm start`. Always resolve the active feature folder by reading `.super-manus/active` first — never hard-code a path.

## 2. What goes in which file

**`task_plan.md`** — the spine.
- `## Goal`: one paragraph, immutable across the feature lifetime.
- `## Phases`: markdown table with columns `# | Name | Status | Notes`.
- Status values: `pending` / `in_progress` / `blocked` / `closed` (lowercase, exact). The `## Outstanding` section in `progress.md` is regenerated from this table by parsing those exact strings — typos break the regen.

**`findings.md`** — your working memory on disk.
- `## Decisions`: dated entries — what was chosen, why, what alternatives were ruled out.
- `## Errors`: table with columns `When | What failed | Resolution`.
- `## Data points / research`: free-form — smoke results, screenshots-as-text, eval numbers, links.

**`progress.md`** — auto-managed; treat as read-only by default.
- `## Completed commits`: the post-commit hook appends one line per `git commit`.
- `## Session log`: the Stop hook appends one paragraph at session end.
- `## Outstanding`: regenerated from `task_plan.md` by `scripts/refresh-outstanding.sh` — never edit by hand.

## 3. When to update each file

| File | Trigger |
|---|---|
| `task_plan.md` | A phase status changes (closed / in_progress / blocked); a new phase is added or split. |
| `findings.md` | Any decision (with reasoning), any error encountered, any research finding worth surviving the session. |
| `progress.md` | NEVER directly. Wait for a hook reminder. The PostToolUse (post-commit) hook will tell you to write to `## Completed commits`; the Stop hook will tell you to write to `## Session log`. |

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
- Reordering or renaming the schema headings — hooks parse by heading name (`## Phases`, `## Outstanding`, `## Completed commits`, `## Session log`) and will silently produce wrong output if you rename them.
- Creating ad-hoc files (`notes.md`, `decisions.md`, `todo.md`) inside the feature folder — keep state in the three canonical files.
- Hand-editing `## Outstanding` in `progress.md` — `scripts/refresh-outstanding.sh` will overwrite it on the next refresh.

---

*The 2-action rule and 3-strike error protocol are borrowed from [planning-with-files](https://github.com/OthmanAdi/planning-with-files).*
