#!/usr/bin/env bash
# Tests skills/systematic-debugging-in-phase/SKILL.md — 5-step debugging checklist
# the orchestrator (and impl-code-writer) follows when a phase test or
# ## Verification command fails. No-clear-cause path appends to findings.md
# ## Errors and surfaces to user; do NOT iterate blindly.

set -euo pipefail
cd "$(dirname "$0")/.."
F="skills/systematic-debugging-in-phase/SKILL.md"
[ -f "$F" ] || { echo "FAIL: $F missing"; exit 1; }

# Frontmatter — name + non-empty description
python3 - <<'PY' || { echo "FAIL: frontmatter check failed"; exit 1; }
import re
with open("skills/systematic-debugging-in-phase/SKILL.md") as f:
    text = f.read()
m = re.match(r'^---\n(.*?)\n---\n', text, re.DOTALL)
assert m, "missing YAML frontmatter block"
fm = m.group(1)
keys = {}
for line in fm.splitlines():
    if ':' in line:
        k, _, v = line.partition(':')
        keys[k.strip()] = v.strip()
assert keys.get("name") == "systematic-debugging-in-phase", \
    f"name must be 'systematic-debugging-in-phase', got {keys.get('name')!r}"
desc = keys.get("description", "")
assert len(desc) >= 40, f"description must be >=40 chars, got {len(desc)}"
PY

# 5-step checklist. Accept either numbered "1." through "5." OR "Step 1" through "Step 5".
# Verify all five anchors are present.
five_step_ok=1
for n in 1 2 3 4 5; do
  if ! grep -qE "^### Step ${n}|^${n}\.|Step ${n} —" "$F"; then
    five_step_ok=0
    break
  fi
done
if [ "$five_step_ok" -ne 1 ]; then
  echo "FAIL: must contain a 5-step checklist (Step 1..Step 5 or 1...5.)"
  exit 1
fi

# Each step's load-bearing concept: Approach / failing test / binary / regression / fix.
for concept in "Approach" "failing" "[Bb]inary" "regression" "[Ff]ix"; do
  grep -qE "$concept" "$F" || { echo "FAIL: 5-step checklist must mention concept matching: $concept"; exit 1; }
done

# No-clear-cause path: appends to findings.md ## Errors, surfaces to user, do NOT iterate.
grep -qF "findings.md" "$F" || { echo "FAIL: no-clear-cause path must reference findings.md"; exit 1; }
grep -qF "## Errors" "$F" || { echo "FAIL: no-clear-cause path must append to findings.md ## Errors"; exit 1; }
grep -qiE "surface.*user|surface to the user|surface to user" "$F" \
  || { echo "FAIL: no-clear-cause path must surface to the user"; exit 1; }
grep -qiE "do NOT.*iterat|not iterat.*blindly|iterating blindly|iterate blindly" "$F" \
  || { echo "FAIL: no-clear-cause path must say 'do NOT iterate blindly'"; exit 1; }

echo OK
