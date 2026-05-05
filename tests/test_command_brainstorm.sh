#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=commands/brainstorm.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }

# Frontmatter
grep -qF "description:" "$F" || { echo "FAIL: missing frontmatter description"; exit 1; }

# Must reference active feature resolution
grep -qF ".super-manus/active" "$F" || { echo "FAIL: must instruct agent to read .super-manus/active"; exit 1; }
grep -qF "/super-manus:start" "$F" || { echo "FAIL: must point users without active feature to /super-manus:start"; exit 1; }

# Must mention the 5 PRD sections in the writing instructions
for section in Problem Demo Must "Nice-to-have" "Not doing"; do
  grep -qF "## $section" "$F" || { echo "FAIL: must reference '## $section' section"; exit 1; }
done

# Must enforce hard constraints on what NOT to ask
for forbidden in "database" "API" "architecture"; do
  grep -qiF "$forbidden" "$F" || { echo "FAIL: must explicitly forbid asking about $forbidden"; exit 1; }
done

# Must mention 500 words / word cap
grep -qF "500" "$F" || { echo "FAIL: must mention 500-word cap"; exit 1; }

# Must produce updates to task_plan.md ## Goal and ## Phases
grep -qF "task_plan.md" "$F" || { echo "FAIL: must reference task_plan.md"; exit 1; }
grep -qF "## Goal" "$F" || { echo "FAIL: must reference task_plan.md ## Goal update"; exit 1; }
grep -qF "## Phases" "$F" || { echo "FAIL: must reference task_plan.md ## Phases update"; exit 1; }

# Must NOT recommend writing tasks/p<n>_impl.md from brainstorm (that's the next command)
grep -qiF "Do not propose architecture" "$F" || { echo "FAIL: must prohibit proposing architecture"; exit 1; }

echo OK
