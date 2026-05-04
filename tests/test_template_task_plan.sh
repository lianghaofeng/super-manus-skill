#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/task_plan.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }
grep -q "^# Task Plan:" "$F" || { echo "FAIL: missing title heading"; exit 1; }
grep -q "^## Goal" "$F" || { echo "FAIL: missing Goal section"; exit 1; }
grep -q "^## Phases" "$F" || { echo "FAIL: missing Phases section"; exit 1; }
grep -qF "| # | Name | Status | Notes |" "$F" || { echo "FAIL: missing Phases table header"; exit 1; }
echo OK
