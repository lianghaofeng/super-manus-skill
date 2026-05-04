#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/task_plan.md" <<'EOF'
# Task Plan: feature-all-closed

## Goal
All phases closed.

## Phases

| # | Name | Status | Notes |
|---|---|---|---|
| 1 | bootstrap | closed | done |
| 2 | implement core | closed | done |
| 3 | polish docs | closed | done |
EOF

cp tests/fixtures/feature-A/progress.md "$TMP/progress.md"

bash scripts/refresh-outstanding.sh "$TMP" || { echo "FAIL: script exited non-zero"; exit 1; }

grep -qF "(no outstanding phases)" "$TMP/progress.md" || { echo "FAIL: expected '(no outstanding phases)' line"; exit 1; }
if grep -q "^- \[P" "$TMP/progress.md"; then echo "FAIL: no phase lines should appear when all phases are closed"; exit 1; fi
grep -q "^## Outstanding$" "$TMP/progress.md" || { echo "FAIL: Outstanding heading lost"; exit 1; }
grep -q "auto-regenerated" "$TMP/progress.md" || { echo "FAIL: auto-regenerated comment lost"; exit 1; }
grep -q "^## Completed commits$" "$TMP/progress.md" || { echo "FAIL: Completed commits section lost"; exit 1; }
grep -q "^## Session log$" "$TMP/progress.md" || { echo "FAIL: Session log section lost"; exit 1; }

echo OK
