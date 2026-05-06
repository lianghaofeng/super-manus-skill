#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=commands/brainstorm.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }

# Frontmatter
grep -qF "description:" "$F" || { echo "FAIL: missing frontmatter description"; exit 1; }

# v0.4: project-global PRD; no .super-manus/active concept anywhere
grep -qF ".super-manus/active" "$F" && { echo "FAIL: brainstorm.md must NOT reference .super-manus/active in v0.4"; exit 1; } || true
grep -qF "/super-manus:start" "$F" || { echo "FAIL: must point users at /super-manus:start when super-manus is not enabled"; exit 1; }

# v0.4: must operate on project-global prd/_index.md + per-module prd/<module>.md
grep -qF "docs/super-manus/prd/" "$F" || { echo "FAIL: must reference docs/super-manus/prd/ (v0.4 project-global PRD root)"; exit 1; }
grep -qF "prd/_index.md" "$F" || { echo "FAIL: must reference prd/_index.md (v0.4 manifest)"; exit 1; }
grep -qF "prd/<module>.md" "$F" || { echo "FAIL: must reference prd/<module>.md (v0.4 per-module file)"; exit 1; }

# Must reference the prd_index sections it writes
for section in Problem Audience "Success metrics" Demo Must "Not doing" "Modules" "Data flow overview"; do
  grep -qF "## $section" "$F" || { echo "FAIL: must reference '## $section' section in prd/_index.md"; exit 1; }
done

# Must reference the prd_module sections seeded for each module
for section in "Why this exists" Users Success "What users get" "How it connects" "Quality bar" Risks "Out of scope" "Open questions"; do
  grep -qF "## $section" "$F" || { echo "FAIL: must reference '## $section' section for per-module PRD"; exit 1; }
done

# v0.2/v0.4 hard constraints — keep _index.md ≤700 words, per-module ≤2000
grep -qF "700" "$F" || { echo "FAIL: must mention 700-word ceiling for prd/_index.md"; exit 1; }
grep -qF "2000" "$F" || { echo "FAIL: must mention 2000-word ceiling for prd/<module>.md"; exit 1; }

# Must explicitly forbid asking about technical architecture / db / api
for forbidden in "database" "API" "architecture"; do
  grep -qiF "$forbidden" "$F" || { echo "FAIL: must explicitly forbid asking about $forbidden"; exit 1; }
done

# 6-question Q&A: must mention 6 questions and module split is final question
grep -qiE "6 questions|six questions" "$F" || { echo "FAIL: must mention the 6-question contract"; exit 1; }
grep -qiF "module" "$F" || { echo "FAIL: must mention module-split as the final question"; exit 1; }

# v0.4: must NOT auto-seed the first MVP update folder. Brainstorm produces PRD content only.
# /super-manus:sync is what scaffolds impl/<module>/<update>/.
grep -qF "scripts/sm-update.sh" "$F" && { echo "FAIL: brainstorm.md must NOT invoke sm-update.sh in v0.4 — that's /super-manus:sync's job"; exit 1; } || true

# Must explicitly forbid proposing architecture
grep -qiF "Do not propose architecture" "$F" || { echo "FAIL: must prohibit proposing architecture"; exit 1; }

# Must update roadmap.md with the module list
grep -qF "roadmap.md" "$F" || { echo "FAIL: must reference roadmap.md update"; exit 1; }

# Must redirect to /super-manus:sync for first MVP scaffolding (since brainstorm no longer auto-seeds)
grep -qF "/super-manus:sync" "$F" || { echo "FAIL: must redirect to /super-manus:sync for first MVP update folder"; exit 1; }

echo OK
