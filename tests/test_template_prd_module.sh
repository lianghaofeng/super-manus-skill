#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/prd_module.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }
grep -q "^# <module name>" "$F" || { echo "FAIL: missing module name title heading"; exit 1; }
grep -qF "## Why this exists" "$F" || { echo "FAIL: missing 'Why this exists' section"; exit 1; }
grep -qF "## Users" "$F" || { echo "FAIL: missing Users section"; exit 1; }
grep -qF "## Success" "$F" || { echo "FAIL: missing Success section"; exit 1; }
grep -qF "## What users get" "$F" || { echo "FAIL: missing 'What users get' section"; exit 1; }
grep -qF "## How it connects" "$F" || { echo "FAIL: missing 'How it connects' section"; exit 1; }
# Exposes/Consumes semantic preamble — names PM-voice capabilities crossing this module's boundary
# before the structural Upstream/Downstream block. Without this, agents drop back to protocol-only
# edges and module-split decisions lose their semantic anchor (see borrow from Gemini API-First Contract).
grep -qF "Exposes:" "$F" || { echo "FAIL: ## How it connects must declare an Exposes: preamble"; exit 1; }
grep -qF "Consumes:" "$F" || { echo "FAIL: ## How it connects must declare a Consumes: preamble"; exit 1; }
grep -qF "## Quality bar" "$F" || { echo "FAIL: missing 'Quality bar' section"; exit 1; }
grep -qF "## Risks" "$F" || { echo "FAIL: missing Risks section"; exit 1; }
grep -qF "## Out of scope" "$F" || { echo "FAIL: missing 'Out of scope' section"; exit 1; }
grep -qF "## Open questions" "$F" || { echo "FAIL: missing 'Open questions' section"; exit 1; }
grep -qF "<module name>" "$F" || { echo "FAIL: missing <module name> placeholder"; exit 1; }
# Header comment must call out the no-changelog-markers rule
grep -qi "no changelog" "$F" || { echo "FAIL: header should forbid changelog markers"; exit 1; }
# Header comment must call out the 2000-word ceiling
grep -qF "2000 words" "$F" || { echo "FAIL: header should state 2000 words ceiling"; exit 1; }
echo OK
