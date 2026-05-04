# super-manus v0.1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship a Claude Code plugin that gives any project persistent feature-state across `/clear` and `/compact` boundaries via three on-disk files (`task_plan.md` / `findings.md` / `progress.md`) maintained by hook-driven LLM writes.

**Architecture:** Pure plugin — no external services, no API keys. Three SessionStart / Stop / PostToolUse hooks inject one-paragraph reminders into the main agent's context, which then performs all reads/writes. Three slash commands (`/sm start|switch|catchup`) manage the active feature pointer (`.super-manus/active`). One `using-sm` skill teaches the read/write conventions. One pure-shell helper (`refresh-outstanding.sh`) regenerates the read-only Outstanding section without LLM cost.

**Tech Stack:** POSIX shell (bash), markdown templates, JSON manifests. Polyglot `.cmd` wrapper borrowed from superpowers for cross-platform hook invocation. No package manager, no compile step. Tests are bats-style shell scripts (run script in temp dir, assert stdout/files).

**Source design doc:** [`docs/design.md`](../design.md) — read this before starting any task. Sections referenced below as `§N`.

**Repo state at start:** `super-manus/` contains only `docs/design.md` and this plan. NOT a git repo yet — Phase 1 Task 1 initializes it.

---

## Conventions for this plan

- **Working directory** for every command below: `/Users/liangwushang/Documents/StudyPlan/GT/claude/claudeskill/super-manus`. All paths are relative to that root.
- **Test style:** each shell script under `tests/test_<name>.sh` is self-contained, sets up a temp dir, runs the artifact, asserts, and `exit 0` on success. Run with `bash tests/test_<name>.sh`. No test framework dependency.
- **For pure-prose artifacts** (slash command `.md`, skill `SKILL.md`, README, templates): there is no behavioral test — instead, write a structural test that asserts required headings/frontmatter keys are present (`grep -q '^## Goal' templates/task_plan.md`). Skip TDD ceremony when the artifact is just a prompt; do write the structural test.
- **Commit cadence:** one commit per task. Conventional commits prefix: `feat:` / `chore:` / `test:` / `docs:` / `fix:`.
- **Hook output format:** all hooks print a single JSON object on stdout matching Claude Code's hook contract: `{"hookSpecificOutput": {"hookEventName": "<EventName>", "additionalContext": "<text to inject>"}}`. The `additionalContext` becomes a system reminder visible to the main agent. Hooks must `set -euo pipefail` and exit 0 even when there's nothing to inject (emit `{}` in that case so Claude Code doesn't log an error).
- **Hook CWD:** Claude Code runs hooks with the user's project directory as CWD. Scripts can read `./.super-manus/active` directly.
- **DRY:** factor any repeated shell logic (e.g. "resolve active feature folder") into `hooks/lib.sh`, source it from each hook script.

---

## Phase 1 — Repo bootstrap and plugin manifest

Goal: claude-code recognizes a no-op plugin named `super-manus`. Sets the foundation everything else hangs off.

### Task 1.1: Initialize git repo

**Files:**
- Create: `.gitignore`

**Step 1: Init repo and create .gitignore**

```bash
git init
git config user.email "lhf120899@gmail.com"
git config user.name "$(git config --global user.name || echo 'super-manus dev')"
```

`.gitignore`:
```
.DS_Store
.super-manus/
*.swp
node_modules/
```

**Step 2: First commit**

```bash
git add .gitignore docs/
git commit -m "chore: initial repo with design doc"
```

Expected: `git log --oneline` shows one commit.

---

### Task 1.2: Plugin manifest

**Files:**
- Create: `.claude-plugin/plugin.json`
- Test: `tests/test_plugin_manifest.sh`

**Step 1: Write the failing test**

`tests/test_plugin_manifest.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .claude-plugin/plugin.json ] || { echo "FAIL: manifest missing"; exit 1; }
python3 -c "import json,sys; d=json.load(open('.claude-plugin/plugin.json')); assert d['name']=='super-manus', d; assert 'version' in d; assert 'description' in d"
echo OK
```

**Step 2: Run, verify it fails**

```bash
bash tests/test_plugin_manifest.sh
```
Expected: FAIL with "manifest missing".

**Step 3: Implement manifest**

`.claude-plugin/plugin.json`:
```json
{
  "name": "super-manus",
  "description": "Persistent feature-state for Claude Code: survives /clear, generates progress journals from git history",
  "version": "0.1.0",
  "author": { "name": "super-manus contributors" },
  "license": "MIT",
  "keywords": ["state", "persistence", "manus", "planning", "hooks"]
}
```

**Step 4: Run, verify it passes**

```bash
bash tests/test_plugin_manifest.sh
```
Expected: `OK`.

**Step 5: Commit**

```bash
git add .claude-plugin/ tests/
git commit -m "feat: add plugin manifest"
```

---

### Task 1.3: README + LICENSE + CLAUDE.md

**Files:**
- Create: `README.md`, `LICENSE`, `CLAUDE.md`

**Step 1: LICENSE — MIT verbatim**

Copy MIT text (year 2026, holder "super-manus contributors"). Use the standard SPDX-canonical wording from <https://opensource.org/licenses/MIT>.

**Step 2: README.md**

Sections (in order, ~150 lines total):
1. **What** — one paragraph from `design.md §1`.
2. **Why** — one paragraph from `design.md §2`.
3. **Install** — `cd ~/.claude/plugins && git clone <repo> super-manus` then `/plugin reload`.
4. **Quickstart** — `/sm start my-feature` → work → `git commit` → `/clear` → next session resumes automatically.
5. **What it does NOT do** — bullets from `design.md §3 Out` and `§13`.
6. **Coexistence with superpowers** — short blurb from `design.md §9`.
7. **Layout** — copy the tree from `design.md §4`.
8. **Status** — "v0.1, persistence only. v0.2 will add a TDD executor."

**Step 3: CLAUDE.md** (contributor guide for AI agents working on this repo)

Sections:
1. **Repo invariants:** any change touching `hooks/` requires a `tests/test_<name>.sh`; templates must keep their schema headings (`## Goal`, `## Phases`, etc.) verbatim — those headings are read by hooks.
2. **PR governance:** small commits, one logical change per commit, never `git push --force` to `main`, run `bash tests/run-all.sh` before declaring done.
3. **Where to look:** design lives in `docs/design.md`, plans in `docs/plans/`.

**Step 4: No behavioral test.** Just sanity-grep that headings exist:

`tests/test_docs_present.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for f in README.md LICENSE CLAUDE.md; do
  [ -s "$f" ] || { echo "FAIL: $f missing or empty"; exit 1; }
done
grep -q "MIT" LICENSE
grep -q "## Install" README.md
grep -q "## Quickstart" README.md
echo OK
```

Run it, expect OK.

**Step 5: Commit**

```bash
git add README.md LICENSE CLAUDE.md tests/test_docs_present.sh
git commit -m "docs: add README, LICENSE, contributor guide"
```

---

## Phase 2 — Templates

Goal: three template files that `/sm start` will copy. Schema must match `design.md §4`.

### Task 2.1: task_plan.md template

**Files:**
- Create: `templates/task_plan.md`
- Test: `tests/test_template_task_plan.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/task_plan.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }
grep -q "^# Task Plan:" "$F"
grep -q "^## Goal" "$F"
grep -q "^## Phases" "$F"
grep -q "| # | Name | Status | Notes |" "$F"
echo OK
```

**Step 2: Run, expect FAIL.**

**Step 3: Implement template** matching `design.md §4` task_plan.md schema verbatim. Use `<feature title>` as a placeholder that `/sm start` will substitute. Include a one-line HTML comment at top stating "this file is auto-injected by SessionStart — keep headings stable".

**Step 4: Run, expect OK. Commit.**

```bash
git add templates/task_plan.md tests/test_template_task_plan.sh
git commit -m "feat: add task_plan.md template"
```

---

### Task 2.2: findings.md template

Same TDD pattern. Required headings (per `design.md §4`): `# Findings:`, `## Decisions`, `## Errors`, `## Data points / research`. Errors section must contain the table header `| When | What failed | Resolution |`.

Test asserts headings present. Commit `feat: add findings.md template`.

---

### Task 2.3: progress.md template

Required headings: `# Progress:`, `## Completed commits`, `## Session log`, `## Outstanding`. Each section gets a one-line HTML comment explaining its trigger:
- `## Completed commits` — "auto-appended by post-commit hook"
- `## Session log` — "auto-appended by Stop hook at session end"
- `## Outstanding` — "auto-regenerated from task_plan.md by scripts/refresh-outstanding.sh; do not edit by hand"

Test asserts all four headings + the three HTML comments. Commit `feat: add progress.md template`.

---

## Phase 3 — `refresh-outstanding.sh` (pure-shell, no LLM)

Goal: a script that reads `task_plan.md`, extracts non-`closed` rows from the Phases table, rewrites the `## Outstanding` section in `progress.md`. Build this BEFORE the LLM hooks because the post-commit hook will invoke it.

### Task 3.1: Test fixture

**Files:**
- Create: `tests/fixtures/feature-A/task_plan.md`
- Create: `tests/fixtures/feature-A/progress.md`

Minimal task_plan.md fixture with three phases (one closed, one in_progress, one pending). Minimal progress.md with `## Outstanding` empty.

Commit `test: add refresh-outstanding fixtures`.

---

### Task 3.2: refresh-outstanding.sh

**Files:**
- Create: `scripts/refresh-outstanding.sh`
- Test: `tests/test_refresh_outstanding.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
cp tests/fixtures/feature-A/* "$TMP/"
bash scripts/refresh-outstanding.sh "$TMP"
grep -q "^- \[P2\] .* (in_progress)" "$TMP/progress.md"
grep -q "^- \[P3\] .* (pending)" "$TMP/progress.md"
! grep -q "^- \[P1\]" "$TMP/progress.md"   # closed phase must be omitted
rm -rf "$TMP"
echo OK
```

**Step 2: Run, expect FAIL.**

**Step 3: Implement the script.** Argument: feature folder path. Algorithm:
1. `awk` on `task_plan.md` to extract rows of the Phases table where status column != `closed`. Output lines like `- [P<N>] <name> (<status>)`.
2. Build new `## Outstanding` section text.
3. Use `sed` (or awk) to replace the existing `## Outstanding` section (from heading to next `^## ` heading or EOF) atomically (write to `.tmp`, then `mv`).

Constraint: pure POSIX shell + awk + sed. No python, no jq.

**Step 4: Run, expect OK. Commit `feat: add refresh-outstanding script`.**

---

### Task 3.3: Edge cases

Add three more tests (each its own file under `tests/`):
- `test_refresh_all_closed.sh`: all phases closed → Outstanding section becomes literally `(no outstanding phases)`.
- `test_refresh_no_outstanding_section.sh`: progress.md missing `## Outstanding` → script appends it at EOF.
- `test_refresh_idempotent.sh`: run script twice, second run produces zero diff (`diff` exits 0).

Implement fixes if any fail. Commit `test: refresh-outstanding edge cases`.

---

## Phase 4 — Polyglot wrapper + hook scaffolding

Goal: copy superpowers' `run-hook.cmd` pattern verbatim, set up empty hook scripts so `hooks.json` validates.

### Task 4.1: run-hook.cmd

**Files:**
- Create: `hooks/run-hook.cmd`

Verbatim copy from [`/Users/liangwushang/.claude/plugins/cache/superpowers-marketplace/superpowers/4.0.3/hooks/run-hook.cmd`](file:///Users/liangwushang/.claude/plugins/cache/superpowers-marketplace/superpowers/4.0.3/hooks/run-hook.cmd) (verified during research). Two-section file: cmd.exe header in heredoc, then unix shell tail. Make it executable: `chmod +x hooks/run-hook.cmd`.

No test. Commit `feat: add polyglot run-hook wrapper`.

---

### Task 4.2: hooks/lib.sh — shared helpers

**Files:**
- Create: `hooks/lib.sh`
- Test: `tests/test_hooks_lib.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source hooks/lib.sh
TMP=$(mktemp -d); cd "$TMP"
mkdir -p .super-manus docs/super-manus/2026-05-04-foo
echo "2026-05-04-foo" > .super-manus/active
[ "$(sm_active_folder)" = "docs/super-manus/2026-05-04-foo" ] || { echo "FAIL active"; exit 1; }

cd "$TMP" && rm .super-manus/active
[ -z "$(sm_active_folder)" ] || { echo "FAIL no-active should be empty"; exit 1; }

# emit_context: takes hook event name + text, prints valid JSON
out=$(emit_context "SessionStart" "hello world")
echo "$out" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); assert d['hookSpecificOutput']['hookEventName']=='SessionStart'; assert d['hookSpecificOutput']['additionalContext']=='hello world'"

echo OK
```

**Step 2: Run, expect FAIL.**

**Step 3: Implement `hooks/lib.sh`** with two functions:

```bash
sm_active_folder() {
  # Echo absolute-or-relative path of active feature folder, or empty string if none.
  local active_file=".super-manus/active"
  [ -f "$active_file" ] || return 0
  local name; name=$(tr -d '[:space:]' < "$active_file")
  [ -n "$name" ] || return 0
  echo "docs/super-manus/$name"
}

emit_context() {
  # $1 = hookEventName, $2 = text to inject. Emits JSON to stdout.
  local event="$1" text="$2"
  python3 -c "
import json,sys
print(json.dumps({'hookSpecificOutput':{'hookEventName':sys.argv[1],'additionalContext':sys.argv[2]}}))
" "$event" "$text"
}
```

(Note: we use python3 only for JSON escaping. It's preinstalled on macOS + Linux. If we need to drop the python3 dep later, replace with the pure-bash escape function from superpowers' `session-start.sh`.)

**Step 4: Run, expect OK. Commit `feat: add hooks/lib.sh shared helpers`.**

---

### Task 4.3: Empty hooks + hooks.json

**Files:**
- Create: `hooks/session-start.sh`, `hooks/session-end.sh`, `hooks/post-commit.sh`
- Create: `hooks/hooks.json`
- Test: `tests/test_hooks_json.sh`

**Step 1: Write the failing test**

Asserts `hooks.json` parses, has all three event keys (`SessionStart`, `Stop`, `PostToolUse`), each command references `${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd`, and the matchers match `design.md §5`.

**Step 2: Run, expect FAIL.**

**Step 3: Stub each hook script** to be a no-op that emits `{}`:

```bash
#!/usr/bin/env bash
set -euo pipefail
echo '{}'
```

`chmod +x` all three.

**Step 4: Write `hooks/hooks.json`** verbatim from `design.md §5` (matchers `startup|clear|compact` for SessionStart; `Bash` for PostToolUse; no matcher for Stop).

**Step 5: Run, expect OK. Commit `feat: scaffold hook scripts and hooks.json`.**

---

## Phase 5 — Slash commands

Goal: `/sm start`, `/sm switch`, `/sm catchup` work. Slash commands are markdown prompt files; the LLM reads them and executes the described shell. We test by simulating the shell parts in the test runner — but the prose itself we just structurally validate.

### Task 5.1: /sm start

**Files:**
- Create: `commands/start.md`
- Test: `tests/test_command_start_logic.sh`

**Step 1: Write the failing test (logic test only — exercises the shell snippet that the prompt instructs the LLM to run)**

Test plan:
1. Set up temp project dir.
2. Run the canonical commands the slash command tells the LLM to run:
   - validate name (regex `^[a-z0-9][a-z0-9-]*$`)
   - compute `docs/super-manus/$(date +%F)-<name>/`
   - mkdir, cp templates, sed-substitute `<feature title>` → name, write `.super-manus/active`
3. Assert: folder exists, three template files exist with `<feature title>` replaced, `.super-manus/active` contains the folder basename.
4. Assert: re-running with same name exits non-zero.

Implement as `tests/test_command_start_logic.sh` calling a small helper script `scripts/sm-start.sh` that the slash command's body delegates to. (Pulling logic into a script keeps it testable; the slash command file just calls the script and explains semantics.)

**Step 2: Run, expect FAIL.**

**Step 3: Implement `scripts/sm-start.sh`** with the four-step algorithm above. Echoes the created folder path on success; echoes error to stderr and `exit 1` on conflict / bad name.

**Step 4: Implement `commands/start.md`** as a Claude Code slash command file with frontmatter:

```markdown
---
description: Create a new super-manus feature folder and set it active
---

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/sm-start.sh "$ARGUMENTS"` from the project root.

If the script exits non-zero, surface the stderr to the user verbatim.
On success, tell the user: "Started feature `<name>` at `<path>`. Run `/sm catchup` any time to re-load the plan."
```

**Step 5: Run test, expect OK. Commit `feat: /sm start command`.**

---

### Task 5.2: /sm switch

Same pattern as 5.1.

`scripts/sm-switch.sh <name>`:
1. List `docs/super-manus/*/` folders.
2. Match exact basename, or unique substring of basename (after the date prefix).
3. If 0 matches: error.
4. If >1 match: error listing all matches.
5. Else: write basename to `.super-manus/active`, echo confirmation.

`commands/switch.md`: thin wrapper, same shape as start.md.

`tests/test_command_switch_logic.sh`: builds three fake feature folders, asserts exact match wins, unique substring matches, ambiguous fails, missing fails.

Commit `feat: /sm switch command`.

---

### Task 5.3: /sm catchup

`commands/catchup.md`: tells the main agent to re-run the session-start hook script directly:

```markdown
---
description: Re-inject current super-manus feature plan into context
---

Run `bash ${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh` and treat its `additionalContext` as authoritative current state.
```

No script needed (the hook script itself is the implementation).
No new logic test (covered by Phase 6 session-start tests).

Commit `feat: /sm catchup command`.

---

## Phase 6 — SessionStart hook (catchup)

Goal: when a new session starts, hook reads `.super-manus/active`, looks up the feature folder, injects `task_plan.md` plus a pointer line.

### Task 6.1: Implementation

**Files:**
- Modify: `hooks/session-start.sh`
- Test: `tests/test_hook_session_start.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d); cp -r hooks scripts templates "$TMP/"
cd "$TMP"

# Case 1: no .super-manus/active → emits the "no active feature" reminder
out=$(bash hooks/session-start.sh)
echo "$out" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); assert 'no active super-manus feature' in d['hookSpecificOutput']['additionalContext']"

# Case 2: active feature with task_plan.md → injects file content
mkdir -p .super-manus docs/super-manus/2026-05-04-demo
echo "2026-05-04-demo" > .super-manus/active
cp templates/task_plan.md docs/super-manus/2026-05-04-demo/task_plan.md
sed -i.bak 's/<feature title>/demo/g' docs/super-manus/2026-05-04-demo/task_plan.md && rm docs/super-manus/2026-05-04-demo/task_plan.md.bak

out=$(bash hooks/session-start.sh)
echo "$out" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
ctx=d['hookSpecificOutput']['additionalContext']
assert '# Task Plan: demo' in ctx, ctx
assert 'findings.md' in ctx, ctx
assert 'progress.md' in ctx, ctx
"

cd /; rm -rf "$TMP"
echo OK
```

**Step 2: Run, expect FAIL.**

**Step 3: Implement `hooks/session-start.sh`:**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

folder=$(sm_active_folder || true)
if [ -z "$folder" ] || [ ! -f "$folder/task_plan.md" ]; then
  emit_context "SessionStart" "No active super-manus feature in this project. Run \`/sm start <name>\` to begin one, or \`/sm switch <name>\` to resume an existing one."
  exit 0
fi

plan=$(cat "$folder/task_plan.md")
text=$(printf '%s\n\nFurther context for this feature lives in:\n- %s/findings.md (decisions, errors, research)\n- %s/progress.md (commit log, session log, outstanding phases)\n\nRead/update those as the using-sm skill prescribes.' "$plan" "$folder" "$folder")
emit_context "SessionStart" "$text"
```

**Step 4: Run, expect OK. Commit `feat: SessionStart hook injects active task_plan`.**

---

### Task 6.2: Manual smoke test (non-blocking)

Document a smoke procedure in `tests/SMOKE.md`:
1. Symlink the repo into `~/.claude/plugins/super-manus`.
2. In a sandbox project: run `/sm start smoketest`, then `/clear`, then prompt the agent "what feature are we on?" — expect it to reference the demo plan.

This is a checklist for the human, not an automated test. Commit `docs: smoke test procedure`.

---

## Phase 7 — PostToolUse hook (D-trigger / commit)

Goal: when main agent finishes a `git commit`, hook injects "append entry to progress.md".

### Task 7.1: Detect a successful git commit

The PostToolUse hook receives a JSON payload on stdin describing the tool call. We need to inspect: was the tool `Bash`, was the command a `git commit ...`, did it exit 0?

**Files:**
- Modify: `hooks/post-commit.sh`
- Test: `tests/test_hook_post_commit.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d); cp -r hooks scripts templates "$TMP/"
cd "$TMP"
mkdir -p .super-manus docs/super-manus/2026-05-04-demo
echo "2026-05-04-demo" > .super-manus/active
cp templates/task_plan.md docs/super-manus/2026-05-04-demo/

# Case 1: non-commit Bash call → empty {} output
payload='{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"interrupted":false}}'
out=$(echo "$payload" | bash hooks/post-commit.sh)
[ "$out" = "{}" ] || { echo "FAIL: expected {} for non-commit, got: $out"; exit 1; }

# Case 2: failed git commit → empty {}
payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m foo"},"tool_response":{"stdout":"","stderr":"nothing to commit","interrupted":false},"exit_code":1}'
out=$(echo "$payload" | bash hooks/post-commit.sh)
[ "$out" = "{}" ] || { echo "FAIL: expected {} for failed commit"; exit 1; }

# Case 3: successful git commit → emits SessionStart-shaped reminder mentioning progress.md
payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"feat: add x\""},"tool_response":{"stdout":"[main abc1234] feat: add x","stderr":"","interrupted":false},"exit_code":0}'
out=$(echo "$payload" | bash hooks/post-commit.sh)
echo "$out" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
ctx=d['hookSpecificOutput']['additionalContext']
assert 'progress.md' in ctx
assert 'Completed commits' in ctx
assert 'task_plan.md' in ctx  # mentions phase update
"

cd /; rm -rf "$TMP"
echo OK
```

**Step 2: Run, expect FAIL.**

**Step 3: Implement `hooks/post-commit.sh`:**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

payload=$(cat)

# Extract fields with python3 (avoid jq dep)
read -r tool_name command exit_code < <(python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
print(d.get('tool_name',''), end=' ')
cmd=d.get('tool_input',{}).get('command','')
# Replace whitespace in cmd to keep it on one field
print(cmd.split()[0] if cmd else '', end=' ')
print(d.get('exit_code', d.get('tool_response',{}).get('exit_code', 0)))
" <<< "$payload")

# Only proceed for successful Bash git-commits.
if [ "$tool_name" != "Bash" ] || [ "$command" != "git" ]; then echo '{}'; exit 0; fi
# We checked the first word was 'git'; verify second word is 'commit'.
full_cmd=$(python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('tool_input',{}).get('command',''))" <<< "$payload")
case "$full_cmd" in
  "git commit"*|"git "*"commit"*) : ;;
  *) echo '{}'; exit 0 ;;
esac
[ "$exit_code" = "0" ] || { echo '{}'; exit 0; }

folder=$(sm_active_folder || true)
[ -n "$folder" ] || { echo '{}'; exit 0; }

text="A \`git commit\` just succeeded. Per the using-sm skill: append a one-line entry to \`$folder/progress.md\` under \`## Completed commits\`. Format: \`- <YYYY-MM-DD HH:MM> · \\\`<short hash>\\\` · <phase impact> — <one-sentence summary>\`. If this commit closed a phase, also update the matching row in \`$folder/task_plan.md\` Phases table to \`closed\`. After both writes, run \`bash \${CLAUDE_PLUGIN_ROOT}/scripts/refresh-outstanding.sh $folder\` to refresh the Outstanding section."

emit_context "PostToolUse" "$text"
```

**Step 4: Run, expect OK. Commit `feat: PostToolUse hook prompts progress.md update on git commit`.**

---

### Task 7.2: Edge case — `git commit --amend` and aliased commits

Add tests:
- `git commit --amend --no-edit` exit 0 → still triggers (treat as commit).
- `git ci ...` (alias) → does NOT trigger (we check literal `git commit`). Document this limitation in `using-sm` skill.

If passing, commit `test: post-commit edge cases`.

---

## Phase 8 — Stop hook (B-trigger / session end)

Goal: at session end, inject "write a session log paragraph".

### Task 8.1: Implementation

**Files:**
- Modify: `hooks/session-end.sh`
- Test: `tests/test_hook_session_end.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d); cp -r hooks scripts templates "$TMP/"
cd "$TMP"

# Case 1: no active feature → {}
out=$(bash hooks/session-end.sh)
[ "$out" = "{}" ] || { echo "FAIL: expected {} when inactive"; exit 1; }

# Case 2: active feature → injects reminder about Session log + Completed commits
mkdir -p .super-manus docs/super-manus/2026-05-04-demo
echo "2026-05-04-demo" > .super-manus/active
cp templates/progress.md docs/super-manus/2026-05-04-demo/

out=$(bash hooks/session-end.sh)
echo "$out" | python3 -c "
import json,sys
d=json.loads(sys.stdin.read())
ctx=d['hookSpecificOutput']['additionalContext']
assert 'Session log' in ctx
assert 'Completed commits' in ctx
assert 're-read' in ctx.lower()  # design.md §11 risk: explicitly tell agent to re-read
"

cd /; rm -rf "$TMP"
echo OK
```

**Step 2: Run, expect FAIL.**

**Step 3: Implement `hooks/session-end.sh`:**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

folder=$(sm_active_folder || true)
[ -n "$folder" ] || { echo '{}'; exit 0; }
[ -f "$folder/progress.md" ] || { echo '{}'; exit 0; }

text="Session ending. Before stopping, write a session log entry. Steps:
1. Re-read \`$folder/progress.md ## Completed commits\` — those are the source of truth, not your memory.
2. Identify entries added this session.
3. Append a new entry to \`$folder/progress.md ## Session log\`, format:
   ### Session <YYYY-MM-DD> #<N> (<HH:MM> – <HH:MM>)
   - <closed phases / key commits>
   - 卡点 / blockers
   - Next session should first: <one concrete action>
4. If any phase is now blocked, also flip its row in \`$folder/task_plan.md\` to \`blocked\` with a one-line note."

emit_context "Stop" "$text"
```

**Step 4: Run, expect OK. Commit `feat: Stop hook prompts session log write`.**

---

## Phase 9 — `using-sm` skill

Goal: codify the read/write protocol for the main agent.

### Task 9.1: Skill file

**Files:**
- Create: `skills/using-sm/SKILL.md`
- Test: `tests/test_skill_using_sm.sh`

**Step 1: Write the failing test** — assert frontmatter has `name: using-sm`, `description:` present (≥40 chars). Assert body has all 6 sections from `design.md §7`.

**Step 2: Run, expect FAIL.**

**Step 3: Write `SKILL.md`** with frontmatter + the 6 numbered sections from `design.md §7`. Each section ≤120 words. The 2-action rule and 3-strike error protocol are borrowed verbatim from planning-with-files; cite the source in a footer line.

Keep it terse — this is a reference skill the agent will re-read.

**Step 4: Run, expect OK. Commit `feat: using-sm skill`.**

---

## Phase 10 — Test runner + final wiring

### Task 10.1: tests/run-all.sh

**Files:**
- Create: `tests/run-all.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
for t in tests/test_*.sh; do
  echo "=== $t ==="
  if ! bash "$t"; then fail=$((fail+1)); fi
done
echo
if [ "$fail" -gt 0 ]; then echo "FAILED: $fail test(s)"; exit 1; fi
echo "ALL PASS ($(ls tests/test_*.sh | wc -l | tr -d ' ') tests)"
```

`chmod +x tests/run-all.sh`. Commit `test: add aggregate runner`.

---

### Task 10.2: Run everything green

Run `bash tests/run-all.sh`. Expect ALL PASS. Fix any regressions surfaced by the aggregate run (cross-test contamination, leftover temp dirs, etc.).

Commit any fixes as `fix: <description>`.

---

### Task 10.3: Dogfood smoke (manual, against this repo itself)

Per `design.md §12` success criteria, run all six checks against this repo:

1. Symlink `super-manus/` → `~/.claude/plugins/super-manus`. Reload Claude Code.
2. In a NEW sandbox project, run `/sm start dogfood-1`. Verify folder + templates appear.
3. Make 2 commits. Verify `progress.md ## Completed commits` got two entries.
4. Run `/clear`. Verify next message shows agent referencing the active feature without prompting.
5. Verify any phase status update lands in `task_plan.md` automatically.
6. End the session. Verify `progress.md ## Session log` got an entry.
7. Open a new session in the sandbox. Verify catchup works without manual reads.

Document any deviations in `docs/dogfood-2026-05-04.md`. If criteria 1–6 all pass, proceed to release.

If anything fails: file as a task in `task_plan.md` of this very repo (we're dogfooding!) and fix before tagging.

---

### Task 10.4: Tag v0.1.0

After dogfood passes:

```bash
git tag -a v0.1.0 -m "v0.1.0 — persistence layer ships"
```

Do NOT push without explicit user confirmation (see [executing actions with care](.) — tagging is local but pushing is shared state).

Commit any final docs adjustments (e.g. update README "Status:" line to "v0.1.0 released").

---

## Out of scope for this plan (deferred to v0.2+)

Per `design.md §13`:
- TDD task executor (`tasks/<id>.md`)
- Subagent dispatch
- Code review integration
- Git worktree integration
- Multi-harness support
- Multi-feature parallel active state
- Phase archive automation (manual procedure documented in `using-sm` only)

Resist scope creep. If a task tempts you toward any of the above, log it in `findings.md ## Decisions` of this very repo as a v0.2 candidate and move on.

---

## Risks specific to this implementation plan

| Risk | Mitigation |
|---|---|
| Hook output format (`hookSpecificOutput.additionalContext`) is wrong for non-SessionStart events | Phase 6 task 6.2 smoke test validates SessionStart end-to-end. If Stop / PostToolUse don't accept this shape, fall back to printing the reminder text directly to stdout (Claude Code surfaces hook stdout). Fix in `lib.sh::emit_context` so all hooks change at once. |
| `python3` unavailable on some user machines | Document `python3` as a requirement in README. If reports come in, port `emit_context` to the pure-bash JSON escape from superpowers' `session-start.sh`. |
| Slash command markdown frontmatter format changes between Claude Code versions | Mirror the exact frontmatter shape used by superpowers' `commands/*.md` at the time of writing — verify against the installed superpowers cache before shipping. |
| `tests/fixtures/feature-A/task_plan.md` diverges from `templates/task_plan.md` over time | Add `tests/test_fixtures_match_templates.sh` that asserts the fixture's heading set ⊇ template's heading set. |
