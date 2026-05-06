#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# v0.4: super-manus is enabled iff docs/super-manus/prd/ exists.
if [ ! -d "docs/super-manus/prd" ]; then
  emit_context "SessionStart" "super-manus is not enabled in this project. Run \`/super-manus:start\` to seed \`docs/super-manus/{prd,impl}/\`, \`roadmap.md\`, and \`prd_drift.md\`."
  exit 0
fi

update_rel=$(sm_active_update || true)
if [ -z "$update_rel" ]; then
  text='super-manus enabled (project-global PRD at docs/super-manus/prd/). No impl/<module>/<update>/ folder yet.

Next: run `/super-manus:brainstorm` to define product spec and split modules, or `/super-manus:sync <module>` to begin a milestone in an already-defined module.'
  emit_context "SessionStart" "$text"
  exit 0
fi

target_dir="docs/super-manus/impl/$update_rel"
plan=$(cat "$target_dir/task_plan.md" 2>/dev/null || echo "(task_plan.md missing in active update)")
prd_index=$(cat "docs/super-manus/prd/_index.md" 2>/dev/null || echo "(prd/_index.md missing)")
text=$(printf 'super-manus active update: %s\n\n--- prd/_index.md ---\n%s\n\n--- task_plan.md ---\n%s\n\n---\n\nFurther context lives in:\n- %s/findings.md (decisions, errors, research)\n- %s/progress.md (commit log, session log, outstanding phases)\n- docs/super-manus/prd/<module>.md (target state per module)\n- docs/super-manus/roadmap.md (module status table)\n- docs/super-manus/prd_drift.md (PRD ↔ implementation drift log)\n\nRun `/super-manus:drive` if you want a one-line decision on the next action. Do not hand-edit progress.md — hooks own it.' \
  "$update_rel" "$prd_index" "$plan" "$target_dir" "$target_dir")

emit_context "SessionStart" "$text"
