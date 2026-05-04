#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Build a task_plan.md with a truncated row in the middle
cat > "$TMP/task_plan.md" <<'EOF'
# Task Plan: malformed-fixture

## Goal
Test malformed row handling.

## Phases

| # | Name | Status | Notes |
|---|---|---|---|
| 1 | good row alpha | pending | |
| 2 | only three cells |
| 3 | good row gamma | in_progress | |
EOF

cp tests/fixtures/feature-A/progress.md "$TMP/"

# Capture stderr; script should still exit 0 (best-effort)
stderr_out=$(bash scripts/refresh-outstanding.sh "$TMP" 2>&1 >/dev/null) || { echo "FAIL: script should not exit non-zero on malformed row"; exit 1; }

# Stderr must contain a warning mentioning the malformed row
echo "$stderr_out" | grep -q "malformed" || { echo "FAIL: expected stderr warning containing 'malformed', got: $stderr_out"; exit 1; }

# The two well-formed rows must still render
grep -q "^- \[P1\] good row alpha (pending)$" "$TMP/progress.md" || { echo "FAIL: P1 missing from output"; exit 1; }
grep -q "^- \[P3\] good row gamma (in_progress)$" "$TMP/progress.md" || { echo "FAIL: P3 missing from output"; exit 1; }

# The malformed row must NOT appear (no `- [P2]` line)
if grep -q "^- \[P2\]" "$TMP/progress.md"; then echo "FAIL: malformed P2 should not have been emitted"; exit 1; fi

echo OK
