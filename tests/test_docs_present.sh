#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for f in README.md LICENSE CLAUDE.md; do
  [ -s "$f" ] || { echo "FAIL: $f missing or empty"; exit 1; }
done
grep -q "MIT" LICENSE
grep -q "## Install" README.md
grep -q "## Quickstart" README.md
echo OK
