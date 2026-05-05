#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/roadmap.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }
grep -q "^# Roadmap" "$F" || { echo "FAIL: missing Roadmap title heading"; exit 1; }
grep -q "^## Modules" "$F" || { echo "FAIL: missing Modules section"; exit 1; }
grep -qF "| Module | Status | Note |" "$F" || { echo "FAIL: missing Modules table header"; exit 1; }
# All four canonical status values must appear at least in the legend / comment
for s in not-started iterating stable blocked; do
  grep -qF "$s" "$F" || { echo "FAIL: status legend missing '$s'"; exit 1; }
done
echo OK
