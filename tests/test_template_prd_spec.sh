#!/usr/bin/env bash
# Tests templates/prd_spec.md — the v0.9.5 R7 per-module engineering reference.
# Sibling to prd/<module>.md but engineering voice. Heading set is stable
# (hooks/scripts/agents parse by exact match).

set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/prd_spec.md
[ -f "$F" ] || { echo "FAIL: missing $F"; exit 1; }

# H1 placeholder
grep -q "^# <module name>" "$F" || { echo "FAIL: missing '# <module name>' H1"; exit 1; }

# 4 stable H2 sections — exact match
for h in "## Data contracts" "## Interface contracts" "## Behavioral contracts" "## Design rationale"; do
  grep -qF "$h" "$F" || { echo "FAIL: missing H2 '$h'"; exit 1; }
done

# Interface contracts has Exposes / Consumes sub-headings
grep -qF "### Exposes" "$F" || { echo "FAIL: ## Interface contracts must have ### Exposes sub-section"; exit 1; }
grep -qF "### Consumes" "$F" || { echo "FAIL: ## Interface contracts must have ### Consumes sub-section"; exit 1; }

# Stateless placeholder for Data contracts (the (none — ...) pattern that satisfies required-mode)
grep -qF "(none — module is stateless)" "$F" || { echo "FAIL: must include the '(none — module is stateless)' placeholder for Data contracts"; exit 1; }

# Header comment carries the soft word cap (~3000 words of prose)
grep -qF "3000 words" "$F" || { echo "FAIL: header comment should state the ~3000 words soft cap"; exit 1; }

# Header comment must call out engineering voice + sibling-to-PRD framing
grep -qiE "engineering voice" "$F" || { echo "FAIL: header comment should call out engineering voice"; exit 1; }
grep -qiE "sibling|prd/<module>\.md" "$F" || { echo "FAIL: header comment should reference its sibling prd/<module>.md"; exit 1; }

# No changelog markers rule (same as prd_module.md / prd_index.md)
grep -qiE "no changelog|changelog markers" "$F" || { echo "FAIL: header should forbid changelog markers"; exit 1; }

# Stable headings clause (parsed by hooks/scripts/agents)
grep -qiE "Headings are stable|hooks.*parse.*exact match|exact match" "$F" || { echo "FAIL: header should declare headings stable"; exit 1; }

echo OK
