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

# Stop hooks fire at the end of EACH agent reply, not just at session end.
# Triggering a session-log write on every reply spams progress.md, so we count
# turns and only trigger every N turns (default 10; override via env).
# State file format: "<session_id> <turn_count>" on a single line.
state_file="$folder/.session-state"
session_id=$(sm_payload_field "$payload" "session_id")
[ -n "$session_id" ] || session_id="unknown"
threshold="${SUPER_MANUS_LOG_EVERY_N_TURNS:-10}"

# Agent just finished writing per our previous block. Reset counter and stop.
if sm_stop_hook_active "$payload"; then
  printf '%s 0\n' "$session_id" > "$state_file"
  echo '{}'; exit 0
fi

# Read prior state; reset counter on a session change.
prev_id=""; count=0
if [ -f "$state_file" ]; then
  read -r prev_id count < "$state_file" || true
fi
[ "$prev_id" = "$session_id" ] || count=0

# This turn counts. Persist immediately so we don't lose state on crash.
count=$((count + 1))
printf '%s %d\n' "$session_id" "$count" > "$state_file"

# Below threshold → no-op for this turn.
if [ "$count" -lt "$threshold" ]; then
  echo '{}'; exit 0
fi

text="Session ending. Re-read \`$folder/progress.md ## Completed commits\` (source of truth), then prepend one entry to \`## Session log\`: \`### Session <YYYY-MM-DD> #<N> (<HH:MM>–<HH:MM>)\` + 3 bullets (closed phases / blockers / next session first action). If any phase is now blocked, flip its row in \`$folder/task_plan.md\` to \`blocked\`."

emit_context "Stop" "$text"
