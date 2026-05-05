#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=commands/reverse-prd.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }

# Frontmatter
grep -qF "description:" "$F" || { echo "FAIL: missing frontmatter description"; exit 1; }

# Must operate within an active super-manus feature
grep -qF ".super-manus/active" "$F" || { echo "FAIL: must read .super-manus/active"; exit 1; }

# Must produce v0.2 PRD-folder layout: prd/_index.md + per-module prd/<module>.md
grep -qF "prd/_index.md" "$F" || { echo "FAIL: must produce prd/_index.md"; exit 1; }
grep -qF "prd/<module>.md" "$F" || { echo "FAIL: must produce per-module prd/<module>.md files"; exit 1; }

# Must update roadmap.md with the inferred modules
grep -qF "roadmap.md" "$F" || { echo "FAIL: must update roadmap.md"; exit 1; }

# Must be one-shot — user audits afterwards (not interactive Q&A)
grep -qiF "audit" "$F" || { echo "FAIL: must instruct the user to audit/refine after generation"; exit 1; }
grep -qiE "one-shot|one shot" "$F" || { echo "FAIL: must call out the one-shot nature of the command"; exit 1; }

# Must scan project sources to infer module breakdown
grep -qiE "scan|infer|analyze" "$F" || { echo "FAIL: must mention scanning / inferring from project sources"; exit 1; }

# Must NOT seed any impl/<m>/<u>/ folders — that's /super-manus:sync's job
grep -qF "/super-manus:sync" "$F" || { echo "FAIL: must redirect to /super-manus:sync for module work after audit"; exit 1; }

# Must respect 700 / 2000 word ceilings just like /brainstorm
grep -qF "700" "$F" || { echo "FAIL: must mention 700-word ceiling for prd/_index.md"; exit 1; }
grep -qF "2000" "$F" || { echo "FAIL: must mention 2000-word ceiling for prd/<module>.md"; exit 1; }

# Must not invent product details that aren't in the source — instructions to be conservative
grep -qiE "invent|guess|fabricate|conservative" "$F" || { echo "FAIL: must instruct the agent to NOT invent details not visible in the source"; exit 1; }

echo OK
