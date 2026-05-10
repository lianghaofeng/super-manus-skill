# super-manus shared hook helpers — source from any hook script.
# Defines:
#   sm_active_update      — echoes "<module>/<update-folder>" of the most recently
#                           modified update under docs/super-manus/impl/<module>/*/,
#                           or empty if none exist
#   emit_context EVENT TEXT — emits a hook JSON object on stdout
#
# v0.4 layout: PRD / roadmap / prd_drift live at docs/super-manus/ (project-global).
# There is no per-feature wrapper folder and no .super-manus/active state file.
# Active update is resolved purely by mtime scan.

# Resolve python interpreter (some Git Bash installs only have `python`)
if ! command -v python3 >/dev/null 2>&1; then
  python3() { python "$@"; }
  export -f python3 2>/dev/null || true
fi

emit_context() {
  local event="$1" text="$2"
  python3 - "$event" "$text" <<'PY'
import json, sys
event, text = sys.argv[1], sys.argv[2]
# Claude Code hook output schema (as of 2026-05):
#   - UserPromptSubmit / PostToolUse / PostToolBatch / SessionStart accept
#     hookSpecificOutput.additionalContext to inject text into the model.
#   - Stop / SubagentStop need {"decision": "block", "reason": text}; this prevents
#     the agent from stopping and feeds `reason` back as a continuation prompt.
#     The hook MUST guard against stop_hook_active=true to avoid an infinite loop.
#   - Anything else falls back to systemMessage (terminal-visible only).
EVENTS_WITH_ADDITIONAL_CONTEXT = {"UserPromptSubmit", "PostToolUse", "PostToolBatch", "SessionStart"}
STOP_EVENTS = {"Stop", "SubagentStop"}
if event in EVENTS_WITH_ADDITIONAL_CONTEXT:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": event, "additionalContext": text}}))
elif event in STOP_EVENTS:
    print(json.dumps({"decision": "block", "reason": text}))
else:
    print(json.dumps({"systemMessage": text}))
PY
}

# Returns 0 (true) if the given Stop-hook payload has stop_hook_active=true.
# Caller passes the stdin payload as $1; empty / malformed payload is treated as false.
sm_stop_hook_active() {
  local payload="${1:-}"
  [ -n "$payload" ] || return 1
  printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    sys.exit(1)
sys.exit(0 if d.get("stop_hook_active", False) else 1)
'
}

# Echo the value of a top-level string field in the Stop-hook payload (e.g. "session_id").
# Empty output if payload is missing, malformed, or field absent.
sm_payload_field() {
  local payload="${1:-}" field="${2:-}"
  [ -n "$payload" ] || return 0
  [ -n "$field" ] || return 0
  printf '%s' "$payload" | FIELD="$field" python3 -c '
import json, os, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)
v = d.get(os.environ["FIELD"], "")
if isinstance(v, str):
    sys.stdout.write(v)
'
}

# Echoes "<module>/<update-folder-name>" of the most recently modified update folder
# under docs/super-manus/impl/<module>/*/, or nothing if there are no update folders.
# Used by hooks (post-commit, session-end) and /super-manus:impl / /super-manus:drive
# / /super-manus:catchup to resolve "where do I write progress.md right now?" — there
# is no separate active-update state file in v0.4.
sm_active_update() {
  local impl_root="docs/super-manus/impl"
  [ -d "$impl_root" ] || return 0
  python3 - "$impl_root" <<'PY'
import os, sys
root = sys.argv[1]
best = None
best_mtime = -1.0
try:
    for module in os.listdir(root):
        mdir = os.path.join(root, module)
        if not os.path.isdir(mdir):
            continue
        for update in os.listdir(mdir):
            udir = os.path.join(mdir, update)
            if not os.path.isdir(udir):
                continue
            try:
                m = os.path.getmtime(udir)
            except OSError:
                continue
            if m > best_mtime:
                best_mtime = m
                best = f"{module}/{update}"
except FileNotFoundError:
    sys.exit(0)
if best:
    print(best)
PY
}

# Returns 0 (true) if progress.md has commits in `## Completed commits` whose
# latest timestamp is newer than the latest entry in `## Session log`. That is:
# there is real activity (a commit) that has not yet been narrated in the log.
# Returns 1 if up-to-date or no commits at all. Empty / missing file → 1.
sm_has_unlogged_commits() {
  local file="${1:-}"
  [ -n "$file" ] && [ -f "$file" ] || return 1
  python3 - "$file" <<'PY'
import re, sys
try:
    text = open(sys.argv[1]).read()
except Exception:
    sys.exit(1)
commit_ts = None
log_ts = None
section = None
for line in text.splitlines():
    if line.startswith("## "):
        if "Completed commits" in line:
            section = "commits"
        elif "Session log" in line:
            section = "log"
        else:
            section = None
        continue
    if section == "commits":
        m = re.match(r"^\s*-\s+(\d{4}-\d{2}-\d{2} \d{2}:\d{2})", line)
        if m and (commit_ts is None or m.group(1) > commit_ts):
            commit_ts = m.group(1)
    elif section == "log":
        m = re.match(r"^###\s*Session\s+(\d{4}-\d{2}-\d{2})\s+#\d+\s*\((\d{2}:\d{2})", line)
        if m:
            ts = f"{m.group(1)} {m.group(2)}"
            if log_ts is None or ts > log_ts:
                log_ts = ts
if commit_ts is None:
    sys.exit(1)
if log_ts is None:
    sys.exit(0)
sys.exit(0 if commit_ts > log_ts else 1)
PY
}

# v0.8.1: per-project model override for subagent spawns.
#
# Looks up `.super-manus/agents.yml` (project-global static user preference,
# committed to the user's repo) and echoes the override model name for the
# given agent, or empty string if no override is set. The orchestrator main
# thread reads this output before spawning a subagent and, if non-empty,
# passes `model: <value>` to the Agent tool — overriding the agent file's
# frontmatter default.
#
# Schema is intentionally a flat YAML-ish key-value list to dodge external
# parser deps:
#
#   # .super-manus/agents.yml
#   impl-architect: opus
#   impl-reviewer: opus
#   reverse-prd-architect: sonnet     # user wants cheaper PRD synthesis
#   impl-test-writer: opus
#   impl-code-writer: sonnet          # user wants cheaper coding
#   sync-planner: opus
#
# Lines starting with `#` are comments; blank lines ignored. Only `model:` is
# overridable here — `effort:` is plugin-author-pinned in the agent file
# frontmatter and intentionally not user-tweakable (Claude Code's Agent tool
# does not expose `effort` at spawn time, so override would be a no-op).
#
# `.super-manus/` holds STATIC user preferences only. It must not be used for
# dynamic runtime state (active update, session caches, etc.) — those still
# resolve from filesystem mtime via `sm_active_update` and similar helpers.
#
# Returns: agent's override model name (opus|sonnet|haiku) on stdout if
# configured, empty string otherwise. Always exits 0; missing file / missing
# entry / commented-out entry are all "no override".
sm_agent_model() {
  local agent="${1:-}"
  [ -n "$agent" ] || return 0
  local cfg=".super-manus/agents.yml"
  [ -f "$cfg" ] || return 0
  # Match `<agent>: <model>` ignoring leading/trailing whitespace and trailing
  # `#` comments. Reject malformed lines and unknown model values silently.
  local raw
  raw=$(grep -E "^[[:space:]]*${agent}[[:space:]]*:" "$cfg" 2>/dev/null \
        | head -1 \
        | sed -E "s/^[[:space:]]*${agent}[[:space:]]*:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]+\$//" \
        || true)
  case "$raw" in
    opus|sonnet|haiku) printf '%s' "$raw" ;;
    *) ;;  # empty / unknown / commented-out → no override
  esac
}

# v0.9.4 (R4): parse a phase plan's `## Files touched` section into a
# newline-separated list of bare file paths. Used by /super-manus:impl Step 5
# pre-spawn working-tree check and post-return commit whitelist check.
#
# Bullet syntax accepted (one path per bullet):
#   - src/foo.py — short description
#   - `src/foo.py` (new)
#   * src/foo.py
#
# Backticks around the path are stripped. Em-dash / en-dash / parenthesis
# annotations after the path are dropped. Sub-bullets and indented continuation
# lines are ignored. Section boundary is the next `## ` H2.
#
# Returns empty on missing file / missing section. Always exits 0.
sm_parse_files_touched() {
  local plan_file="${1:-}"
  [ -n "$plan_file" ] && [ -f "$plan_file" ] || return 0
  python3 - "$plan_file" <<'PY'
import re, sys
try:
    text = open(sys.argv[1]).read()
except Exception:
    sys.exit(0)
in_section = False
for line in text.splitlines():
    if line.startswith("## "):
        in_section = (line.strip() == "## Files touched")
        continue
    if not in_section:
        continue
    m = re.match(r"^[-*]\s+(.+?)$", line)  # top-level bullet only, no leading indent
    if not m:
        continue
    rest = m.group(1).strip().strip("`")
    m2 = re.match(r"^([^\s—–(`]+)", rest)
    if m2:
        path = m2.group(1).rstrip("`")
        if path:
            print(path)
PY
}

# v0.9.4 (R4): check whether a file path matches any entry in a newline-separated
# whitelist. Exact match OR per-segment glob match (fnmatch, `*` does NOT cross
# `/` — `lib/*.py` matches `lib/jwt.py` but NOT `lib/nested/x.py`). Recursive
# globs (`**`) are silently treated as literal `*` per segment; the design
# disallows recursive expansion for safety.
#
# Returns 0 (true) on match, 1 (false) otherwise. Empty file or empty whitelist
# returns 1.
sm_whitelist_match() {
  local file="${1:-}"
  local whitelist="${2:-}"
  [ -n "$file" ] || return 1
  [ -n "$whitelist" ] || return 1
  printf '%s' "$whitelist" | FILE="$file" python3 -c '
import os, sys, fnmatch
file = os.environ["FILE"]
file_parts = file.split("/")
for pattern in sys.stdin.read().splitlines():
    pattern = pattern.strip()
    if not pattern:
        continue
    pattern_parts = pattern.split("/")
    if len(pattern_parts) != len(file_parts):
        continue
    if all(fnmatch.fnmatchcase(fp, pp) for fp, pp in zip(file_parts, pattern_parts)):
        sys.exit(0)
sys.exit(1)
'
}
