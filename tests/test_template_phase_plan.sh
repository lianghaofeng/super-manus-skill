#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/phase_plan.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }
grep -q "^# Phase <n>:" "$F" || { echo "FAIL: missing title heading"; exit 1; }
grep -q "^## Objective" "$F" || { echo "FAIL: missing Objective section"; exit 1; }
grep -q "^## Approach" "$F" || { echo "FAIL: missing Approach section"; exit 1; }
grep -q "^## Edge cases" "$F" || { echo "FAIL: missing Edge cases section (v0.9.0 — must enumerate 3-5 concrete edges anchored in PRD ## Quality bar / ## Risks)"; exit 1; }
grep -q "^## Files touched" "$F" || { echo "FAIL: missing Files touched section"; exit 1; }
grep -q "^## Verification" "$F" || { echo "FAIL: missing Verification section"; exit 1; }
grep -qF "<phase name>" "$F" || { echo "FAIL: missing <phase name> placeholder"; exit 1; }

# v0.9.0: Edge cases section ordering — must sit between Approach and Files touched
# (architect's idempotency + insertion logic depends on this position)
awk '/^## Approach/{a=NR} /^## Edge cases/{e=NR} /^## Files touched/{f=NR} END{exit !(a && e && f && a<e && e<f)}' "$F" \
  || { echo "FAIL: ## Edge cases must sit between ## Approach and ## Files touched"; exit 1; }

# v0.9.0: template comment must guide architect away from vague enumeration
grep -qiE "anchored in PRD" "$F" || { echo "FAIL: Edge cases template guidance must require PRD anchoring"; exit 1; }
grep -qiE "error_handling: yes|error handling.{0,5}vague|untestable" "$F" || { echo "FAIL: Edge cases template guidance must call out vague labels as bad"; exit 1; }
echo OK
