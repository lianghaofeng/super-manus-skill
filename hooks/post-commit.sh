#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# Read the tool-call payload from stdin (Claude Code passes JSON for PostToolUse hooks)
payload=$(cat)

# Extract fields via three small python3 invocations — robust against tabs/newlines in
# the command string. Each invocation is silent on malformed JSON (returns empty / 0).
tool_name=$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    print(""); sys.exit(0)
print(d.get("tool_name", ""))
')

cmd=$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    print(""); sys.exit(0)
print(d.get("tool_input", {}).get("command", ""))
')

exit_code=$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read())
except Exception:
    print("0"); sys.exit(0)
ec = d.get("exit_code", d.get("tool_response", {}).get("exit_code", 0))
print(ec)
')

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

text="A \`git commit\` just succeeded. Per the using-sm skill: append a one-line entry to \`$folder/progress.md\` under \`## Completed commits\`. Use this format:

\`- <YYYY-MM-DD HH:MM> · \\\`<short-hash>\\\` · <phase impact, e.g. closed P1, advanced P2, no phase change> — <one-sentence summary of the change>\`

If this commit closed a phase, also update the matching row in \`$folder/task_plan.md\` Phases table to \`closed\`. After both writes, run:

\`\`\`bash
bash \"\${CLAUDE_PLUGIN_ROOT}/scripts/refresh-outstanding.sh\" \"$folder\"
\`\`\`

to regenerate the Outstanding section."

emit_context "PostToolUse" "$text"
