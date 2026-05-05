#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/progress.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }
grep -q "^# Progress:" "$F" || { echo "FAIL: missing title heading"; exit 1; }
grep -q "^## Completed commits" "$F" || { echo "FAIL: missing Completed commits section"; exit 1; }
grep -q "^## Session log" "$F" || { echo "FAIL: missing Session log section"; exit 1; }
grep -q "^## Outstanding" "$F" || { echo "FAIL: missing Outstanding section"; exit 1; }
grep -qF "post-commit hook" "$F" || { echo "FAIL: missing post-commit trigger comment"; exit 1; }
grep -qF "Stop hook" "$F" || { echo "FAIL: missing Stop hook trigger comment"; exit 1; }
grep -qF "auto-regenerated" "$F" || { echo "FAIL: missing auto-regenerated trigger comment"; exit 1; }
echo OK
