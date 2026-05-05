#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# Read Claude Code's stdin payload (may be empty in tests / direct invocation).
payload=$(cat 2>/dev/null || true)

folder=$(sm_active_folder || true)
[ -n "$folder" ] || { echo '{}'; exit 0; }
[ -f "$folder/progress.md" ] || { echo '{}'; exit 0; }

# Sentinel: avoid asking for a session log on every agent turn.
# Stop hooks fire at the end of EACH agent reply, not just at session end.
# We keep a per-feature sentinel containing the session_id of the last session
# we already logged. If the current session_id matches, no-op for the rest of
# the session.
sentinel="$folder/.session-logged"
session_id=$(sm_payload_field "$payload" "session_id")

# If we already blocked once in this stop cycle and the agent is now retrying,
# don't block again — record this session as logged and let the agent stop.
if sm_stop_hook_active "$payload"; then
  [ -n "$session_id" ] && printf '%s' "$session_id" > "$sentinel"
  echo '{}'; exit 0
fi

# Already logged this session? No-op for every subsequent turn.
if [ -n "$session_id" ] && [ -f "$sentinel" ] && [ "$(cat "$sentinel" 2>/dev/null)" = "$session_id" ]; then
  echo '{}'; exit 0
fi

text="Session ending. Re-read \`$folder/progress.md ## Completed commits\` (source of truth), then prepend one entry to \`## Session log\`: \`### Session <YYYY-MM-DD> #<N> (<HH:MM>–<HH:MM>)\` + 3 bullets (closed phases / blockers / next session first action). If any phase is now blocked, flip its row in \`$folder/task_plan.md\` to \`blocked\`."

emit_context "Stop" "$text"
