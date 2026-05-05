#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

folder=$(sm_active_folder || true)

if [ -z "$folder" ] || [ ! -d "$folder" ]; then
  emit_context "SessionStart" "No active super-manus feature in this project. Run \`/super-manus:start <name>\` to begin a new feature, or \`/super-manus:switch <name>\` to resume an existing one."
  exit 0
fi

# v0.2 detection: prd/ as a directory.
if [ -d "$folder/prd" ]; then
  update_rel=$(sm_active_update "$folder")
  if [ -z "$update_rel" ]; then
    text=$(printf 'Active super-manus v0.2 feature: %s. No impl/<module>/<update>/ folder yet.\n\nNext: run `/super-manus:brainstorm` to define product spec and split modules, or `/super-manus:sync <module>` to begin a milestone in an already-defined module.' "$folder")
  else
    target_dir="$folder/impl/$update_rel"
    plan=$(cat "$target_dir/task_plan.md" 2>/dev/null || echo "(task_plan.md missing in active update)")
    text=$(printf 'Active super-manus v0.2 feature: %s\nActive update: %s\n\n--- task_plan.md ---\n%s\n\n---\n\nFurther context lives in:\n- %s/findings.md (decisions, errors, research)\n- %s/progress.md (commit log, session log, outstanding phases)\n- %s/prd/_index.md (feature manifest + module list)\n- %s/prd/<module>.md (target state for this update'"'"'s module)\n\nRun `/super-manus:drive` if you want a one-line decision on the next action. Do not hand-edit progress.md — hooks own it.' \
      "$folder" "$update_rel" "$plan" "$target_dir" "$target_dir" "$folder" "$folder")
  fi
  emit_context "SessionStart" "$text"
  exit 0
fi

# v0.1 fallback: feature root has task_plan.md.
if [ ! -f "$folder/task_plan.md" ]; then
  emit_context "SessionStart" "No active super-manus feature in this project. Run \`/super-manus:start <name>\` to begin a new feature, or \`/super-manus:switch <name>\` to resume an existing one."
  exit 0
fi

plan=$(cat "$folder/task_plan.md")
text=$(printf '%s\n\n---\n\nFurther context for this feature lives in:\n- %s/findings.md (decisions, errors, research notes)\n- %s/progress.md (commit log, session log, outstanding phases)\n\nRead and update these per the using-sm skill conventions. Do not hand-edit progress.md — hooks own it.' "$plan" "$folder" "$folder")

emit_context "SessionStart" "$text"
