# super-manus shared hook helpers — source from any hook script.
# Defines:
#   sm_active_folder      — echoes active feature folder path or empty string
#   emit_context EVENT TEXT — emits a hook JSON object on stdout

sm_active_folder() {
  local active_file=".super-manus/active"
  [ -f "$active_file" ] || return 0
  local name
  name=$(tr -d '[:space:]' < "$active_file")
  [ -n "$name" ] || return 0
  echo "docs/super-manus/$name"
}

emit_context() {
  local event="$1" text="$2"
  python3 - "$event" "$text" <<'PY'
import json, sys
event, text = sys.argv[1], sys.argv[2]
print(json.dumps({"hookSpecificOutput": {"hookEventName": event, "additionalContext": text}}))
PY
}
