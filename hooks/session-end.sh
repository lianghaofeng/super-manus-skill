#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# Read Claude Code's stdin payload (may be empty in tests / direct invocation).
payload=$(cat 2>/dev/null || true)
# If we already blocked once in this stop cycle and the agent is now retrying,
# don't block again — that's an infinite loop. Just no-op so the agent can stop.
if sm_stop_hook_active "$payload"; then
  echo '{}'; exit 0
fi

folder=$(sm_active_folder || true)
[ -n "$folder" ] || { echo '{}'; exit 0; }
[ -f "$folder/progress.md" ] || { echo '{}'; exit 0; }

text="Session ending. Re-read \`$folder/progress.md ## Completed commits\` (source of truth), then prepend one entry to \`## Session log\`: \`### Session <YYYY-MM-DD> #<N> (<HH:MM>–<HH:MM>)\` + 3 bullets (closed phases / blockers / next session first action). If any phase is now blocked, flip its row in \`$folder/task_plan.md\` to \`blocked\`."

emit_context "Stop" "$text"
