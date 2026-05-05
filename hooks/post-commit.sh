#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# Read the tool-call payload from stdin (Claude Code passes JSON for PostToolUse hooks)
payload=$(cat)

# Single python3 fork: parse the JSON once, emit all needed fields tab-separated.
# On parse failure, returns empty tool_name so the next short-circuit fires safely.
fields=$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    print("\t\t0")  # tool_name="", cmd="", exit_code="0" — will short-circuit on tool_name filter
    sys.exit(0)
tool_name = d.get("tool_name", "")
cmd = d.get("tool_input", {}).get("command", "")
ec = d.get("exit_code", d.get("tool_response", {}).get("exit_code", 0))
# Tab-separate. cmd may contain newlines but the join order means tool_name is first
# field and exit_code is last; cmd in the middle absorbs any embedded tabs.
print(f"{tool_name}\t{cmd}\t{ec}")
')

# Split: tool_name = first field, exit_code = last field, cmd = everything between
tool_name="${fields%%$'\t'*}"
exit_code="${fields##*$'\t'}"
cmd_tmp="${fields#*$'\t'}"
cmd="${cmd_tmp%$'\t'*}"

# Filter: only successful Bash git-commit calls
[ "$tool_name" = "Bash" ] || { echo '{}'; exit 0; }
[ "$exit_code" = "0" ] || { echo '{}'; exit 0; }

# Strip leading whitespace from command for the prefix check
cmd_trimmed="${cmd#"${cmd%%[![:space:]]*}"}"
case "$cmd_trimmed" in
  "git commit"|"git commit "*) : ;;
  *) echo '{}'; exit 0 ;;
esac

# Resolve active feature; no-op if none
folder=$(sm_active_folder || true)
[ -n "$folder" ] || { echo '{}'; exit 0; }
[ -d "$folder" ] || { echo '{}'; exit 0; }

# v0.2 detection: prd/ exists as a directory → use the active update's progress.md.
# v0.1 fallback: feature root has progress.md.
if [ -d "$folder/prd" ]; then
  update_rel=$(sm_active_update "$folder")
  if [ -z "$update_rel" ]; then
    # v0.2 feature with no impl/<module>/<update>/ yet — nothing to write to.
    echo '{}'; exit 0
  fi
  target_dir="$folder/impl/$update_rel"
else
  # v0.1: target progress.md / task_plan.md at the feature root.
  target_dir="$folder"
fi

text="A \`git commit\` just succeeded. Per the using-sm skill: append a one-line entry to \`$target_dir/progress.md\` under \`## Completed commits\`. Use this format:

\`- <YYYY-MM-DD HH:MM> · \\\`<short-hash>\\\` · <phase impact, e.g. closed P1, advanced P2, no phase change> — <one-sentence summary of the change>\`

If this commit closed a phase, also update the matching row in \`$target_dir/task_plan.md\` Phases table to \`closed\`. After both writes, run:

\`\`\`bash
bash \"\${CLAUDE_PLUGIN_ROOT}/scripts/refresh-outstanding.sh\" \"$target_dir\"
\`\`\`

to regenerate the Outstanding section."

emit_context "PostToolUse" "$text"
