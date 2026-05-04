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
echo OK
