#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/prd.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }
grep -q "^# PRD:" "$F" || { echo "FAIL: missing PRD title heading"; exit 1; }
grep -q "^## Problem" "$F" || { echo "FAIL: missing Problem section"; exit 1; }
grep -q "^## Demo" "$F" || { echo "FAIL: missing Demo section"; exit 1; }
grep -q "^## Must" "$F" || { echo "FAIL: missing Must section"; exit 1; }
grep -q "^## Nice-to-have" "$F" || { echo "FAIL: missing Nice-to-have section"; exit 1; }
grep -q "^## Not doing" "$F" || { echo "FAIL: missing Not doing section"; exit 1; }
grep -q "^## Success metric" "$F" || { echo "FAIL: missing Success metric section"; exit 1; }
grep -qF "<feature title>" "$F" || { echo "FAIL: missing <feature title> placeholder for sm-start substitution"; exit 1; }
# The header comment must explicitly forbid tech design content
grep -qiF "tasks/p<n>_impl.md" "$F" || { echo "FAIL: header should point tech design to tasks/p<n>_impl.md"; exit 1; }
echo OK
