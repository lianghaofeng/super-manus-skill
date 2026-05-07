#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for f in README.md LICENSE CLAUDE.md; do
  [ -s "$f" ] || { echo "FAIL: $f missing or empty"; exit 1; }
done
grep -q "MIT" LICENSE
grep -q "## Install" README.md
grep -q "## How to use it" README.md
grep -q "## Directory layout" README.md
grep -q "## Updating an existing PRD" README.md
grep -q "### \`prd-update\` — two modes" README.md
grep -q "## Drift detection" README.md
grep -q "## Updates" README.md
echo OK
