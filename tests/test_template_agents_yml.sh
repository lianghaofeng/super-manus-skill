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
# v0.9.5 R9: reverse-prd-architect renamed to reverse-architect.
for agent in impl-architect impl-reviewer reverse-architect impl-test-writer impl-code-writer sync-planner; do
  grep -qE "^#?${agent}:" "$F" || { echo "FAIL: template must list agent '${agent}' (commented or active)"; exit 1; }
done
# Negative regression — old name must not leak back in
grep -qE "^#?reverse-prd-architect:" "$F" \
  && { echo "FAIL: v0.9.5 R9 must NOT list the old agent name 'reverse-prd-architect' (renamed to reverse-architect)"; exit 1; } || true

# Every agent line MUST be commented out in the seeded default — the file is
# documentation by default; users uncomment to opt in to overrides.
active_overrides=$(grep -cE "^[a-z][a-z0-9-]*:" "$F" || true)
[ "$active_overrides" = "0" ] || { echo "FAIL: template must have ZERO uncommented agent lines, found $active_overrides"; exit 1; }

# v0.8.2: must document that effort: is overridable via CLAUDE_CODE_EFFORT_LEVEL
# env var (highest priority — overrides frontmatter). The template should not
# silently leave users thinking effort is fixed.
grep -qF "CLAUDE_CODE_EFFORT_LEVEL" "$F" \
  || { echo "FAIL: template must document CLAUDE_CODE_EFFORT_LEVEL as the effort override path"; exit 1; }
grep -qiE "highest.*priority|highest-priority|wins|overrides.*frontmatter" "$F" \
  || { echo "FAIL: template must clarify env var has highest priority (overrides plugin frontmatter)"; exit 1; }
# Must NOT carry the old (wrong) claim that effort is unoverridable
if grep -qiE "effort.*not.*overridable|effort.*is NOT.*overridable" "$F"; then
  echo "FAIL: template still claims effort is not overridable (it IS, via env var) — remove that claim"
  exit 1
fi

# Must document that the file is for STATIC user prefs, not dynamic state —
# this is the load-bearing distinction with the v0.3-era .super-manus/active.
grep -qiE "static|preference" "$F" \
  || { echo "FAIL: template must document static-preference role of .super-manus/"; exit 1; }

# Must list valid model values
grep -qE "opus.*sonnet.*haiku|opus \| sonnet \| haiku" "$F" \
  || { echo "FAIL: template must enumerate valid model values (opus/sonnet/haiku)"; exit 1; }

echo OK
