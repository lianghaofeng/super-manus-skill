#!/usr/bin/env bash
# Tests templates/agents.yml — the v0.8.1 default per-project agent-model
# override config seeded by sm-start.sh into <project>/.super-manus/agents.yml.
# Out-of-the-box, every agent line MUST be commented out: enabling super-manus
# in a fresh project should NOT silently change which model the user pays for.

set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/agents.yml

[ -f "$F" ] || { echo "FAIL: missing $F"; exit 1; }

# All six agents MUST be listed (commented or not) so users see the full surface.
for agent in impl-architect impl-reviewer reverse-prd-architect impl-test-writer impl-code-writer sync-planner; do
  grep -qE "^#?${agent}:" "$F" || { echo "FAIL: template must list agent '${agent}' (commented or active)"; exit 1; }
done

# Every agent line MUST be commented out in the seeded default — the file is
# documentation by default; users uncomment to opt in to overrides.
active_overrides=$(grep -cE "^[a-z][a-z0-9-]*:" "$F" || true)
[ "$active_overrides" = "0" ] || { echo "FAIL: template must have ZERO uncommented agent lines, found $active_overrides"; exit 1; }

# Must document that effort: is NOT overridable (avoid users wasting time
# editing a no-op).
grep -qiE "effort.*not.*overridable|effort.*not.*here|not exposed.*effort" "$F" \
  || { echo "FAIL: template must explain effort: is not overridable"; exit 1; }

# Must document that the file is for STATIC user prefs, not dynamic state —
# this is the load-bearing distinction with the v0.3-era .super-manus/active.
grep -qiE "static|preference" "$F" \
  || { echo "FAIL: template must document static-preference role of .super-manus/"; exit 1; }

# Must list valid model values
grep -qE "opus.*sonnet.*haiku|opus \| sonnet \| haiku" "$F" \
  || { echo "FAIL: template must enumerate valid model values (opus/sonnet/haiku)"; exit 1; }

echo OK
