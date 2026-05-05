#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/phase_plan.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }
grep -q "^# Phase <n>:" "$F" || { echo "FAIL: missing title heading"; exit 1; }
grep -q "^## Objective" "$F" || { echo "FAIL: missing Objective section"; exit 1; }
grep -q "^## Approach" "$F" || { echo "FAIL: missing Approach section"; exit 1; }
grep -q "^## Files touched" "$F" || { echo "FAIL: missing Files touched section"; exit 1; }
grep -q "^## Verification" "$F" || { echo "FAIL: missing Verification section"; exit 1; }
grep -qF "<phase name>" "$F" || { echo "FAIL: missing <phase name> placeholder"; exit 1; }
echo OK
