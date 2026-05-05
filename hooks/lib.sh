# super-manus shared hook helpers — source from any hook script.
# Defines:
#   sm_active_folder      — echoes active feature folder path or empty string
#   emit_context EVENT TEXT — emits a hook JSON object on stdout

# Resolve python interpreter (some Git Bash installs only have `python`)
if ! command -v python3 >/dev/null 2>&1; then
  python3() { python "$@"; }
  export -f python3 2>/dev/null || true
fi

# Returns the path even if the directory does not exist on disk; callers must check.
sm_active_folder() {
  local active_file=".super-manus/active"
  [ -f "$active_file" ] || return 0
  local name
  name=$(tr -d '[:space:]' < "$active_file")
  [ -n "$name" ] || return 0
  case "$name" in
    */*|..*|*/..*) return 0 ;;
  esac
  echo "docs/super-manus/$name"
}

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
# under the given feature folder's impl/ tree, or nothing if there are no update
# folders. Used by hooks (post-commit, session-end) and the /super-manus:impl /
# /super-manus:drive commands to resolve "where do I write progress.md right now?"
# without a separate active-update state file.
sm_active_update() {
  local feature="${1:-}"
  [ -n "$feature" ] && [ -d "$feature/impl" ] || return 0
  python3 - "$feature/impl" <<'PY'
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
