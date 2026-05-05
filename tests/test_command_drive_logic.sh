#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=commands/drive.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }

# Frontmatter
grep -qF "description:" "$F" || { echo "FAIL: missing frontmatter description"; exit 1; }

# Reads the full feature state
grep -qF ".super-manus/active" "$F" || { echo "FAIL: must read .super-manus/active"; exit 1; }
grep -qF "prd/_index.md" "$F" || { echo "FAIL: must read prd/_index.md"; exit 1; }
grep -qF "roadmap.md" "$F" || { echo "FAIL: must read roadmap.md"; exit 1; }
grep -qF "prd_drift.md" "$F" || { echo "FAIL: must read prd_drift.md"; exit 1; }

# Must dispatch to the right next-step command based on state
for cmd in "/super-manus:brainstorm" "/super-manus:sync" "/super-manus:prd-update" "/super-manus:impl" "/super-manus:start"; do
  grep -qF "$cmd" "$F" || { echo "FAIL: must mention dispatch target $cmd"; exit 1; }
done

# Must include drift-scan responsibility
grep -qiF "drift" "$F" || { echo "FAIL: must call out drift scan"; exit 1; }

# Must announce decision + reason in one line before acting (auto-mode friendly)
grep -qiF "decision" "$F" || { echo "FAIL: must announce a decision before acting"; exit 1; }

# Auto-mode: drive should execute, not just plan, when an unambiguous next step exists
grep -qiF "execute" "$F" || { echo "FAIL: must mention executing the chosen next step"; exit 1; }

echo OK
