#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/findings.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }
grep -q "^# Findings:" "$F" || { echo "FAIL: missing title heading"; exit 1; }
grep -q "^## Decisions" "$F" || { echo "FAIL: missing Decisions section"; exit 1; }
grep -q "^## Errors" "$F" || { echo "FAIL: missing Errors section"; exit 1; }
grep -q "^## Data points / research" "$F" || { echo "FAIL: missing Data points / research section"; exit 1; }
grep -qF "| When | What failed | Resolution |" "$F" || { echo "FAIL: missing Errors table header"; exit 1; }

# v0.7.4: Reflexion-style cross-phase memory section
grep -q "^## Reflections" "$F" || { echo "FAIL: missing v0.7.4 Reflections section"; exit 1; }
# Embedded H3 template comment must show the 3-bullet shape
grep -qF "Misstep:" "$F" || { echo "FAIL: Reflections template must include 'Misstep:' bullet"; exit 1; }
grep -qF "Root cause:" "$F" || { echo "FAIL: Reflections template must include 'Root cause:' bullet"; exit 1; }
grep -qF "Heuristic:" "$F" || { echo "FAIL: Reflections template must include 'Heuristic:' bullet (the load-bearing line)"; exit 1; }
# Phase header pattern in template comment
# v0.9.4 R6: heading rename — `### Phase <n>: <name>` → `### <update-slug>/p<n>: <name>`.
# Legacy heading remains valid for pre-v0.9.4 entries (parser handles both); new entries use the renamed form.
grep -qE "### <update-slug>/p<n>:" "$F" \
  || { echo "FAIL: v0.9.4 R6 Reflections template must show '### <update-slug>/p<n>: <name>' H3 header pattern"; exit 1; }

# v0.9.4 R6: per-entry metadata block <!-- meta: ... -->
grep -qF "<!-- meta:" "$F" \
  || { echo "FAIL: v0.9.4 R6 Reflections template must show the <!-- meta: ... --> per-entry metadata block"; exit 1; }
for field in files_touched keywords trigger retries created; do
  grep -qE "${field}:" "$F" \
    || { echo "FAIL: v0.9.4 R6 Reflections metadata block must document '${field}:' field"; exit 1; }
done

# v0.9.4 R6: orchestrator filters cross-UPDATE reflections at architect spawn
grep -qiE "cross-update|cross update|across updates|every findings.md|glob.*findings" "$F" \
  || { echo "FAIL: v0.9.4 R6 template must explain cross-update injection mechanism"; exit 1; }

# Trigger values are constrained
grep -qF "reviewer-RETURN" "$F" \
  || { echo "FAIL: v0.9.4 R6 must document 'reviewer-RETURN' as the auto-write trigger value"; exit 1; }
grep -qF "user-curated" "$F" \
  || { echo "FAIL: v0.9.4 R6 must document 'user-curated' as the manual-write trigger value"; exit 1; }

echo OK
