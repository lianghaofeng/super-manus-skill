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
