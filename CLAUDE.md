# Contributor Guide

This file is for AI agents (and humans) modifying the super-manus plugin itself. Read it before editing.

## Repo invariants

- Any change touching `hooks/` requires a matching `tests/test_<name>.sh`. New hook, new test — no exceptions.
- Templates under `templates/` must keep their schema headings verbatim: `## Goal`, `## Phases`, `## Decisions`, `## Errors`, `## Completed commits`, `## Session log`, `## Outstanding`. These headings are parsed by hooks and scripts; renaming them silently breaks the runtime.
- Plugin manifest (`.claude-plugin/plugin.json`) and hook configuration (`hooks/hooks.json`) are load-bearing. Validate JSON before committing.

## PR governance

- Small commits, one logical change per commit.
- Commit messages follow the conventional style already in `git log` (`feat:`, `fix:`, `docs:`, `chore:`, `test:`).
- Never `git push --force` to `main`. If history needs rewriting, do it on a branch and open a PR.
- Run `bash tests/run-all.sh` before declaring any task done. A green run is the bar — not "looks right to me".
- Never commit `.DS_Store`, editor swap files, or anything outside the four-file commit you intended.

## Where to look

- Design lives in `docs/design.md` — the source of truth for what v0.1 is and is not.
- Plans (task-by-task implementation breakdown) live in `docs/plans/`.
- When in doubt about scope, re-read `design.md §3` (Scope) and `§13` (Out-of-scope clarifications) before adding anything.
