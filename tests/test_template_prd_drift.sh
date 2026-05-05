#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/prd_drift.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }
grep -q "^# PRD drift log" "$F" || { echo "FAIL: missing 'PRD drift log' title"; exit 1; }
grep -qF "| When | Module | Conflict | Resolution |" "$F" || { echo "FAIL: missing drift table header"; exit 1; }
# Header comment must declare the file as append-only
grep -qi "append" "$F" || { echo "FAIL: header should call out append-only semantics"; exit 1; }
echo OK
