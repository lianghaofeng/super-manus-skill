#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp tests/fixtures/feature-A/task_plan.md "$TMP/"
cp tests/fixtures/feature-A/progress.md "$TMP/"
bash scripts/refresh-outstanding.sh "$TMP" || { echo "FAIL: script exited non-zero"; exit 1; }
grep -q "^- \[P2\] implement core (in_progress)$" "$TMP/progress.md" || { echo "FAIL: P2 line missing or wrong format"; exit 1; }
grep -q "^- \[P3\] polish docs (pending)$" "$TMP/progress.md" || { echo "FAIL: P3 line missing or wrong format"; exit 1; }
if grep -q "^- \[P1\]" "$TMP/progress.md"; then echo "FAIL: closed phase P1 should not appear"; exit 1; fi
# Section heading and the auto-regenerated comment must still be present
grep -q "^## Outstanding$" "$TMP/progress.md" || { echo "FAIL: Outstanding heading lost"; exit 1; }
grep -q "auto-regenerated" "$TMP/progress.md" || { echo "FAIL: auto-regenerated comment lost"; exit 1; }
# Other sections must still be present (script must not stomp the rest)
grep -q "^## Completed commits$" "$TMP/progress.md" || { echo "FAIL: Completed commits section lost"; exit 1; }
grep -q "^## Session log$" "$TMP/progress.md" || { echo "FAIL: Session log section lost"; exit 1; }
echo OK
