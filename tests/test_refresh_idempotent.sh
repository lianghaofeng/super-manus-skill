#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cp tests/fixtures/feature-A/task_plan.md "$TMP/task_plan.md"
cp tests/fixtures/feature-A/progress.md "$TMP/progress.md"

bash scripts/refresh-outstanding.sh "$TMP" || { echo "FAIL: first run exited non-zero"; exit 1; }
cp "$TMP/progress.md" "$TMP/progress.after-run-1.md"

bash scripts/refresh-outstanding.sh "$TMP" || { echo "FAIL: second run exited non-zero"; exit 1; }

if ! diff -q "$TMP/progress.after-run-1.md" "$TMP/progress.md" > /dev/null; then
  echo "FAIL: script is not idempotent — second run changed the file"
  diff "$TMP/progress.after-run-1.md" "$TMP/progress.md" || true
  exit 1
fi

echo OK
