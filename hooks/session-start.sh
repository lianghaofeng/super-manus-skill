#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

folder=$(sm_active_folder || true)

if [ -z "$folder" ] || [ ! -f "$folder/task_plan.md" ]; then
  emit_context "SessionStart" "No active super-manus feature in this project. Run \`/super-manus:start <name>\` to begin a new feature, or \`/super-manus:switch <name>\` to resume an existing one."
  exit 0
fi

plan=$(cat "$folder/task_plan.md")

# Build the injected text: the full plan, then a pointer line to the sibling files.
text=$(printf '%s\n\n---\n\nFurther context for this feature lives in:\n- %s/findings.md (decisions, errors, research notes)\n- %s/progress.md (commit log, session log, outstanding phases)\n\nRead and update these per the using-sm skill conventions. Do not hand-edit progress.md — hooks own it.' "$plan" "$folder" "$folder")

emit_context "SessionStart" "$text"
