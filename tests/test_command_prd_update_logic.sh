#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=commands/prd-update.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }

# Frontmatter
grep -qF "description:" "$F" || { echo "FAIL: missing frontmatter description"; exit 1; }

# Must resolve active feature from .super-manus/active
grep -qF ".super-manus/active" "$F" || { echo "FAIL: must read .super-manus/active"; exit 1; }

# Must operate on a single per-module PRD file
grep -qF "prd/<module>.md" "$F" || { echo "FAIL: must reference prd/<module>.md (per-module PRD)"; exit 1; }

# The 5 surgical-edit options must all be documented
for opt in Tighten Split Demote Exclude Add; do
  grep -qF "$opt" "$F" || { echo "FAIL: must document the '$opt' edit option"; exit 1; }
done

# Hard constraints — no changelog markers, no multi-section rewrites, ≤2000 words
grep -qiF "no changelog" "$F" || { echo "FAIL: must forbid changelog markers"; exit 1; }
grep -qiF "minimum" "$F" || { echo "FAIL: must call out minimum / surgical edit constraint"; exit 1; }
grep -qF "2000" "$F" || { echo "FAIL: must mention 2000-word ceiling for the module file"; exit 1; }
grep -qiF "brainstorm" "$F" || { echo "FAIL: must redirect multi-section rewrites to /super-manus:brainstorm"; exit 1; }

# Must write a paired findings.md decision entry in the active update folder
grep -qF "findings.md" "$F" || { echo "FAIL: must write a paired findings.md decision entry"; exit 1; }

# Must NOT write to progress.md (hook-managed)
grep -qiF "progress.md" "$F" || { echo "FAIL: must mention progress.md (specifically: not to write to it)"; exit 1; }

# Must NOT touch prd_drift.md directly here either (drift is logged by /sync or /impl, resolved by prd-update via the findings.md entry)
# (No grep needed — this is a forbidden behavior; just check the file exists and doesn't claim to write drift)

# Must redirect tech-design changes back to impl/<module>/<update>/tasks/
grep -qiF "tech" "$F" || { echo "FAIL: must distinguish product vs tech changes"; exit 1; }

# Tighten / Demote options must verify the affected bullet against the actual code via using-sm's Drift check protocol
grep -qF "Drift check protocol" "$F" || { echo "FAIL: prd-update.md must reference using-sm's Drift check protocol for Tighten/Demote verification"; exit 1; }
grep -qF "LSP" "$F" || { echo "FAIL: prd-update.md must use LSP to verify the bullet against current code (not just trust the user)"; exit 1; }

echo OK
