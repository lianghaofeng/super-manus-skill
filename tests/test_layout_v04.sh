#!/usr/bin/env bash
# Layout-invariant test: project-global PRD path + no .super-manus/active state file.
# Originated in v0.4 layout migration; assertions are now phrased against the
# current state, not the v0.3->v0.4 transition (CLAUDE.md no longer carries the
# historical migration narrative).

set -euo pipefail
cd "$(dirname "$0")/.."

# 1. CLAUDE.md says .super-manus/active is gone (semantic invariant).
grep -qE "(no|NO|gone|removed|no longer)[^A-Za-z0-9].*\.super-manus/active|\.super-manus/active.*(no|NO|gone|removed|no longer)" CLAUDE.md \
  || { echo "FAIL: CLAUDE.md must say .super-manus/active is gone/removed/no longer used"; exit 1; }

# 2. CLAUDE.md describes a project-global PRD layout (no per-feature wrapper).
grep -qF "docs/super-manus/prd/" CLAUDE.md \
  || { echo "FAIL: CLAUDE.md must mention docs/super-manus/prd/ as project-global"; exit 1; }
# Negative: CLAUDE.md must NOT recommend a per-feature wrapper as live guidance.
grep -qE "docs/super-manus/<feature>/" CLAUDE.md \
  && { echo "FAIL: CLAUDE.md must NOT use docs/super-manus/<feature>/ as live guidance"; exit 1; } || true

# 3. scripts/sm-start.sh takes 0 arguments
grep -qF 'if [ $# -ne 0 ]' scripts/sm-start.sh \
  || { echo "FAIL: scripts/sm-start.sh must enforce 0 arguments via 'if [ \$# -ne 0 ]'"; exit 1; }

# 4. scripts/sm-update.sh creates folders under docs/super-manus/impl/<module>/ (no feature wrapper)
grep -qE 'base="docs/super-manus"' scripts/sm-update.sh \
  || { echo "FAIL: scripts/sm-update.sh must define base=docs/super-manus (project-global, no feature wrapper)"; exit 1; }
grep -qF '$base/impl/$module/' scripts/sm-update.sh \
  || { echo "FAIL: scripts/sm-update.sh must compose update path as \$base/impl/\$module/ (no feature wrapper)"; exit 1; }
grep -qE 'docs/super-manus/[^/"$]+/impl/' scripts/sm-update.sh \
  && { echo "FAIL: scripts/sm-update.sh must NOT use a per-feature wrapper docs/super-manus/<feature>/impl/"; exit 1; } || true

# 5. hooks/lib.sh defines sm_active_update and does NOT define sm_active_feature / sm_active_folder
grep -qE "^sm_active_update\(\)" hooks/lib.sh \
  || { echo "FAIL: hooks/lib.sh must define sm_active_update()"; exit 1; }
grep -qE "^sm_active_feature\(\)" hooks/lib.sh \
  && { echo "FAIL: hooks/lib.sh must NOT define sm_active_feature()"; exit 1; } || true
grep -qE "^sm_active_folder\(\)" hooks/lib.sh \
  && { echo "FAIL: hooks/lib.sh must NOT define sm_active_folder() (replaced by sm_active_update)"; exit 1; } || true

# 6. No <feature>/ legacy paths leak into live instructions under hooks/ commands/ scripts/ skills/ agents/.
# Documented migration / legacy lines are allowed.
files_to_scan="hooks commands scripts skills agents"
violations=$(grep -rEn 'docs/super-manus/<feature>/|<feature_folder>/impl/<m>/<u>/' \
  $files_to_scan 2>/dev/null || true)
if [ -n "$violations" ]; then
  remaining=$(printf '%s\n' "$violations" \
    | grep -viE "v0\.[123]|migration|legacy|removed|gone|no longer|old path|→|->|now-empty|delete the|archive|fold the" \
    || true)
  if [ -n "$remaining" ]; then
    echo "FAIL: legacy <feature>/ path patterns leaked into hooks/commands/scripts/skills/agents:"
    printf '%s\n' "$remaining"
    exit 1
  fi
fi

# 7. Hooks use the project-global PRD path.
grep -qF "docs/super-manus/prd" hooks/post-commit.sh \
  || { echo "FAIL: hooks/post-commit.sh must use project-global path docs/super-manus/prd"; exit 1; }
grep -qF "docs/super-manus/prd" hooks/session-start.sh \
  || { echo "FAIL: hooks/session-start.sh must use project-global path docs/super-manus/prd"; exit 1; }
grep -qF "docs/super-manus/prd" hooks/session-end.sh \
  || { echo "FAIL: hooks/session-end.sh must use project-global path docs/super-manus/prd"; exit 1; }

echo OK
