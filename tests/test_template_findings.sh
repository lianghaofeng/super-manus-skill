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

# v0.7.4: Reflexion-style cross-phase memory section
grep -q "^## Reflections" "$F" || { echo "FAIL: missing v0.7.4 Reflections section"; exit 1; }
# Embedded H3 template comment must show the 3-bullet shape
grep -qF "Misstep:" "$F" || { echo "FAIL: Reflections template must include 'Misstep:' bullet"; exit 1; }
grep -qF "Root cause:" "$F" || { echo "FAIL: Reflections template must include 'Root cause:' bullet"; exit 1; }
grep -qF "Heuristic:" "$F" || { echo "FAIL: Reflections template must include 'Heuristic:' bullet (the load-bearing line)"; exit 1; }
# Phase header pattern in template comment
grep -qE "### Phase <n>:" "$F" || { echo "FAIL: Reflections template must show '### Phase <n>: <name>' H3 header pattern"; exit 1; }

echo OK
