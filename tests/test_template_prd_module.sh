#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/prd_module.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }
grep -q "^# <module name>" "$F" || { echo "FAIL: missing module name title heading"; exit 1; }
grep -q "^## Purpose" "$F" || { echo "FAIL: missing Purpose section"; exit 1; }
grep -q "^## Surface" "$F" || { echo "FAIL: missing Surface section"; exit 1; }
grep -q "^## Data flow" "$F" || { echo "FAIL: missing Data flow section"; exit 1; }
grep -q "^## Constraints" "$F" || { echo "FAIL: missing Constraints section"; exit 1; }
grep -q "^## Out of scope" "$F" || { echo "FAIL: missing Out of scope section"; exit 1; }
grep -q "^## Open questions" "$F" || { echo "FAIL: missing Open questions section"; exit 1; }
grep -qF "<module name>" "$F" || { echo "FAIL: missing <module name> placeholder"; exit 1; }
# Header comment must call out the no-changelog-markers rule
grep -qi "no changelog" "$F" || { echo "FAIL: header should forbid changelog markers"; exit 1; }
# Header comment must call out the 2000-word ceiling
grep -qF "2000 words" "$F" || { echo "FAIL: header should state 2000 words ceiling"; exit 1; }
echo OK
