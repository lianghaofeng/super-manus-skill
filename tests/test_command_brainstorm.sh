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

# v0.2: must operate on prd/_index.md and per-module prd/<module>.md
grep -qF "prd/_index.md" "$F" || { echo "FAIL: must reference prd/_index.md (v0.2 manifest)"; exit 1; }
grep -qF "prd/<module>.md" "$F" || { echo "FAIL: must reference prd/<module>.md (v0.2 per-module file)"; exit 1; }

# Must reference the prd_index sections it writes
for section in Problem Demo Must "Not doing" "Modules" "Data flow"; do
  grep -qF "## $section" "$F" || { echo "FAIL: must reference '## $section' section in prd/_index.md"; exit 1; }
done

# Must reference the prd_module sections seeded for each module
for section in Purpose Surface Constraints "Out of scope" "Open questions"; do
  grep -qF "## $section" "$F" || { echo "FAIL: must reference '## $section' section for per-module PRD"; exit 1; }
done

# v0.2 hard constraints — keep _index.md ≤700 words, per-module ≤2000
grep -qF "700" "$F" || { echo "FAIL: must mention 700-word ceiling for prd/_index.md"; exit 1; }
grep -qF "2000" "$F" || { echo "FAIL: must mention 2000-word ceiling for prd/<module>.md"; exit 1; }

# Must explicitly forbid asking about technical architecture / db / api
for forbidden in "database" "API" "architecture"; do
  grep -qiF "$forbidden" "$F" || { echo "FAIL: must explicitly forbid asking about $forbidden"; exit 1; }
done

# 5-question Q&A: must mention 5 questions and last question is module split
grep -qF "5 questions" "$F" || { echo "FAIL: must mention the 5-question contract"; exit 1; }
grep -qiF "module" "$F" || { echo "FAIL: must mention module-split as the 5th question"; exit 1; }

# Must auto-seed the first MVP update folder via sm-update.sh
grep -qF "scripts/sm-update.sh" "$F" || { echo "FAIL: must invoke scripts/sm-update.sh to seed first MVP update"; exit 1; }
grep -qiF "mvp" "$F" || { echo "FAIL: must name the first update 'mvp' (or close)"; exit 1; }

# Must NOT recommend writing tasks/p<n>_impl.md from brainstorm (that's /super-manus:impl)
grep -qiF "Do not propose architecture" "$F" || { echo "FAIL: must prohibit proposing architecture"; exit 1; }

# Must update roadmap.md with the module list
grep -qF "roadmap.md" "$F" || { echo "FAIL: must reference roadmap.md update"; exit 1; }

echo OK
