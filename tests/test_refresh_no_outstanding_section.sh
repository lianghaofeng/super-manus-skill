#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cp tests/fixtures/feature-A/task_plan.md "$TMP/task_plan.md"

cat > "$TMP/progress.md" <<'EOF'
# Progress: feature-A

## Completed commits

(no commits yet)

## Session log

(no sessions yet)
EOF

bash scripts/refresh-outstanding.sh "$TMP" || { echo "FAIL: script exited non-zero"; exit 1; }

grep -q "^## Outstanding$" "$TMP/progress.md" || { echo "FAIL: Outstanding section was not appended"; exit 1; }
grep -q "auto-regenerated" "$TMP/progress.md" || { echo "FAIL: auto-regenerated comment missing in appended section"; exit 1; }
grep -q "^- \[P2\] implement core (in_progress)$" "$TMP/progress.md" || { echo "FAIL: P2 line missing in appended section"; exit 1; }
grep -q "^- \[P3\] polish docs (pending)$" "$TMP/progress.md" || { echo "FAIL: P3 line missing in appended section"; exit 1; }
if grep -q "^- \[P1\]" "$TMP/progress.md"; then echo "FAIL: closed P1 should not appear"; exit 1; fi

# Pre-existing sections must still be intact
grep -q "^## Completed commits$" "$TMP/progress.md" || { echo "FAIL: Completed commits section lost"; exit 1; }
grep -q "^## Session log$" "$TMP/progress.md" || { echo "FAIL: Session log section lost"; exit 1; }

# Outstanding must come AFTER Session log (i.e. appended at EOF, not somewhere odd)
session_line=$(grep -n "^## Session log$" "$TMP/progress.md" | head -1 | cut -d: -f1)
outstanding_line=$(grep -n "^## Outstanding$" "$TMP/progress.md" | head -1 | cut -d: -f1)
if [ "$outstanding_line" -le "$session_line" ]; then
  echo "FAIL: Outstanding section did not land after Session log"; exit 1
fi

echo OK
