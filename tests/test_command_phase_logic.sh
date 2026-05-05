#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_ROOT="$(pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

sm_start() {
  SUPER_MANUS_ROOT="$REPO_ROOT" bash "$REPO_ROOT/scripts/sm-start.sh" "$@"
}
sm_phase() {
  SUPER_MANUS_ROOT="$REPO_ROOT" bash "$REPO_ROOT/scripts/sm-phase.sh" "$@"
}

# Case A: invalid number (zero) → exit non-zero
if sm_phase "0" 2>/dev/null; then echo "FAIL: phase 0 should be rejected"; exit 1; fi

# Case B: invalid number (negative / non-numeric) → exit non-zero
if sm_phase "-1" 2>/dev/null; then echo "FAIL: negative phase should be rejected"; exit 1; fi
if sm_phase "abc" 2>/dev/null; then echo "FAIL: non-numeric phase should be rejected"; exit 1; fi

# Case C: no active feature → exit non-zero
if sm_phase "1" 2>/dev/null; then echo "FAIL: missing active feature should be rejected"; exit 1; fi

# Case D: happy path — start a feature, customize phases table, then call /sm phase 1
sm_start "demo" >/dev/null
TODAY=$(date +%F)
FOLDER="docs/super-manus/${TODAY}-demo"
PLAN="$FOLDER/task_plan.md"

# Replace the seeded single phase row with two named phases
python3 - "$PLAN" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text()
old_table = "| 1 | <first phase name> | pending | |"
new_table = "\n".join([
    "| 1 | scaffold-routes | in_progress | |",
    "| 2 | wire-handlers | pending | |",
])
assert old_table in text, "seeded phase row not found"
p.write_text(text.replace(old_table, new_table))
PY

out=$(sm_phase "1")
TARGET="$FOLDER/tasks/p1.md"
[ -f "$TARGET" ] || { echo "FAIL: tasks/p1.md not created at $TARGET"; exit 1; }
grep -q "^# Phase 1: scaffold-routes" "$TARGET" || { echo "FAIL: phase number/name not substituted in $TARGET"; cat "$TARGET"; exit 1; }
grep -q "^## Objective" "$TARGET" || { echo "FAIL: Objective heading missing"; exit 1; }
grep -q "^## Approach" "$TARGET" || { echo "FAIL: Approach heading missing"; exit 1; }
grep -q "^## Files touched" "$TARGET" || { echo "FAIL: Files touched heading missing"; exit 1; }
grep -q "^## Verification" "$TARGET" || { echo "FAIL: Verification heading missing"; exit 1; }
echo "$out" | grep -q "$TARGET" || { echo "FAIL: success output should mention target path, got: $out"; exit 1; }

# Case E: phase number not present in Phases table → exit non-zero
if sm_phase "9" 2>/dev/null; then echo "FAIL: phase 9 (not in table) should be rejected"; exit 1; fi
[ ! -f "$FOLDER/tasks/p9.md" ] || { echo "FAIL: rejected phase should not have left a file"; exit 1; }

# Case F: idempotency — sm_phase 1 a second time must not overwrite, must print same path
echo "USER EDIT" >> "$TARGET"
out2=$(sm_phase "1")
[ -f "$TARGET" ] || { echo "FAIL: target gone after re-run"; exit 1; }
grep -q "USER EDIT" "$TARGET" || { echo "FAIL: re-run overwrote user content"; exit 1; }
echo "$out2" | grep -q "$TARGET" || { echo "FAIL: re-run output should mention target path, got: $out2"; exit 1; }

# Case G: phase 2 (different row) → fresh file with that phase's name
out3=$(sm_phase "2")
TARGET2="$FOLDER/tasks/p2.md"
[ -f "$TARGET2" ] || { echo "FAIL: tasks/p2.md not created"; exit 1; }
grep -q "^# Phase 2: wire-handlers" "$TARGET2" || { echo "FAIL: phase 2 name not substituted"; cat "$TARGET2"; exit 1; }

echo OK
