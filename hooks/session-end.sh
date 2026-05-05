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

text="Session ending. Before stopping, write a session log entry to \`$folder/progress.md\`. Steps:

1. **Re-read** \`$folder/progress.md ## Completed commits\` — those are the source of truth, not your memory of what happened this session.
2. Identify entries added this session (compare against the existing \`## Session log\` to see where the last session ended).
3. Append a new entry to \`$folder/progress.md ## Session log\` (newest first), formatted:

   \`\`\`
   ### Session <YYYY-MM-DD> #<N> (<HH:MM> – <HH:MM>)
   - <closed phases / key commits this session>
   - 卡点 / blockers (if any)
   - Next session should first: <one concrete action>
   \`\`\`

4. If any phase is now blocked, flip its row in \`$folder/task_plan.md\` Phases table to \`blocked\` with a one-line note explaining the block.

Do this BEFORE you stop — the user is waiting on the next session being able to resume cleanly."

emit_context "Stop" "$text"
