#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# Read Claude Code's stdin payload (may be empty in tests / direct invocation).
payload=$(cat 2>/dev/null || true)

# v0.4: super-manus is enabled iff docs/super-manus/prd/ exists.
[ -d "docs/super-manus/prd" ] || { echo '{}'; exit 0; }

update_rel=$(sm_active_update || true)
[ -n "$update_rel" ] || { echo '{}'; exit 0; }

target_dir="docs/super-manus/impl/$update_rel"
[ -f "$target_dir/progress.md" ] || { echo '{}'; exit 0; }

# Stop hooks fire at the end of EACH agent reply, not just at session end.
# Triggering a session-log write on every reply spams progress.md, so we count
# turns and only trigger every N turns (default 5; override via SUPER_MANUS_LOG_EVERY_N_TURNS).
# Cadence policy is governed by SUPER_MANUS_LOG_MODE (turns / commit / both / off).
# State file format: "<session_id> <turn_count>" on a single line.
# State file lives next to progress.md so it tracks per-update state.
state_file="$target_dir/.session-state"
session_id=$(sm_payload_field "$payload" "session_id")
[ -n "$session_id" ] || session_id="unknown"
threshold="${SUPER_MANUS_LOG_EVERY_N_TURNS:-5}"

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

# Trigger mode:
#   both    (default) — fire on whichever comes first: every-N-turns OR new commit
#   turns             — only every-N-turns
#   commit            — only when there's a new commit since last `### Session` entry
#   off               — never auto-fire; users opt-in via /super-manus:log
mode="${SUPER_MANUS_LOG_MODE:-both}"
trigger=0
case "$mode" in
  off)    trigger=0 ;;
  turns)  [ "$count" -ge "$threshold" ] && trigger=1 ;;
  commit) sm_has_unlogged_commits "$target_dir/progress.md" && trigger=1 ;;
  both|*)
    if [ "$count" -ge "$threshold" ]; then trigger=1
    elif sm_has_unlogged_commits "$target_dir/progress.md"; then trigger=1
    fi
    ;;
esac

[ "$trigger" -eq 1 ] || { echo '{}'; exit 0; }

text="Session checkpoint. Re-read \`$target_dir/progress.md ## Completed commits\` (source of truth). Judge: is the activity since the latest \`## Session log\` entry worth a new line? If not, just stop.

If yes, prepend ONE entry to \`## Session log\`:
\`### Session <YYYY-MM-DD> #<N> (<HH:MM>–<HH:MM>)\`
+ at most 3 bullets, each ONE LINE (≤80 English chars / ≤30 Chinese chars): what closed/advanced; blockers (skip if none); Next: one concrete action.

Hard rules: no file paths, no line numbers, no function names, no test commands, no code identifiers, no block-A/B/C breakdowns. Don't restate \`## Completed commits\` — summarise. Standup tone, not status report. If a phase is now blocked, flip its row in \`$target_dir/task_plan.md\` to \`blocked\`."

emit_context "Stop" "$text"
