#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/prd_index.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }
grep -q "^# <feature title>" "$F" || { echo "FAIL: missing feature title heading"; exit 1; }
grep -qF "## Problem" "$F" || { echo "FAIL: missing Problem section"; exit 1; }
grep -qF "## Audience" "$F" || { echo "FAIL: missing Audience section"; exit 1; }
grep -qF "## Success metrics" "$F" || { echo "FAIL: missing 'Success metrics' section"; exit 1; }
grep -qF "## Demo" "$F" || { echo "FAIL: missing Demo section"; exit 1; }
grep -qF "## Must" "$F" || { echo "FAIL: missing Must section"; exit 1; }
grep -qF "## Not doing" "$F" || { echo "FAIL: missing 'Not doing' section"; exit 1; }
grep -qF "## Modules" "$F" || { echo "FAIL: missing Modules section"; exit 1; }
grep -qF "## Data flow overview" "$F" || { echo "FAIL: missing 'Data flow overview' section"; exit 1; }
grep -qF "| Module | File | Purpose |" "$F" || { echo "FAIL: missing Modules table header"; exit 1; }
grep -qF "<feature title>" "$F" || { echo "FAIL: missing <feature title> placeholder for sm-start substitution"; exit 1; }
# Header comment must point at per-module PRD files for module-specific surface
grep -qiF "prd/<module>.md" "$F" || { echo "FAIL: header should point per-module surface to prd/<module>.md"; exit 1; }
echo OK
