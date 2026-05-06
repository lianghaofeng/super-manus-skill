#!/usr/bin/env bash
# Layout-invariant test for v0.4: project-global PRD + path-migration table.
# Asserts that the v0.4 layout invariants documented in CLAUDE.md and the v0.3→v0.4
# path migration table are reflected in scripts, hooks, and agents/commands.

set -euo pipefail
cd "$(dirname "$0")/.."

# 1. CLAUDE.md mentions "v0.4 layout"
grep -qF "v0.4 layout" CLAUDE.md || { echo "FAIL: CLAUDE.md must mention 'v0.4 layout'"; exit 1; }

# 2. CLAUDE.md says .super-manus/active is gone in v0.4
grep -qE "no .super-manus/active.*v0\.4|\\.super-manus/active.*(removed|gone|no longer)" CLAUDE.md || { echo "FAIL: CLAUDE.md must say .super-manus/active is gone/removed in v0.4"; exit 1; }

# 3. CLAUDE.md path migration table includes the 5 OLD→NEW path mappings
for old_path in \
  "docs/super-manus/<feature>/prd/_index.md" \
  "docs/super-manus/<feature>/prd/<module>.md" \
  "docs/super-manus/<feature>/roadmap.md" \
  "docs/super-manus/<feature>/prd_drift.md" \
  "docs/super-manus/<feature>/impl/<m>/<u>/"; do
  grep -qF "$old_path" CLAUDE.md || { echo "FAIL: CLAUDE.md path-migration table missing OLD path '$old_path'"; exit 1; }
done

# Migration table must explicitly reference the v0.3 → v0.4 transition
grep -qE "v0\.3 → v0\.4|v0\.3 →|v0.3 to v0.4|v0\.3-?>v0\.4" CLAUDE.md || { echo "FAIL: CLAUDE.md must label the migration as v0.3 → v0.4"; exit 1; }

# 4. scripts/sm-start.sh takes 0 arguments
grep -qF 'if [ $# -ne 0 ]' scripts/sm-start.sh || { echo "FAIL: scripts/sm-start.sh must enforce 0 arguments via 'if [ \$# -ne 0 ]'"; exit 1; }

# 5. scripts/sm-update.sh creates folders under docs/super-manus/impl/<module>/ (no feature wrapper)
grep -qE 'base="docs/super-manus"' scripts/sm-update.sh || { echo "FAIL: scripts/sm-update.sh must define base=docs/super-manus (project-global, no feature wrapper)"; exit 1; }
grep -qF '$base/impl/$module/' scripts/sm-update.sh || { echo "FAIL: scripts/sm-update.sh must compose update path as \$base/impl/\$module/ (no feature wrapper)"; exit 1; }
# Negative: must NOT compose paths with a feature/<feature> wrapper between super-manus/ and impl/
grep -qE 'docs/super-manus/[^/"$]+/impl/' scripts/sm-update.sh && { echo "FAIL: scripts/sm-update.sh must NOT use a per-feature wrapper docs/super-manus/<feature>/impl/"; exit 1; } || true

# 6. hooks/lib.sh defines sm_active_update and does NOT define sm_active_feature
grep -qE "^sm_active_update\(\)" hooks/lib.sh || { echo "FAIL: hooks/lib.sh must define sm_active_update()"; exit 1; }
grep -qE "^sm_active_feature\(\)" hooks/lib.sh && { echo "FAIL: hooks/lib.sh must NOT define sm_active_feature() in v0.4"; exit 1; } || true
# Also: sm_active_folder is the v0.1/v0.2 helper — must be gone in v0.4
grep -qE "^sm_active_folder\(\)" hooks/lib.sh && { echo "FAIL: hooks/lib.sh must NOT define sm_active_folder() in v0.4 (replaced by sm_active_update)"; exit 1; } || true

# 7. No file under hooks/ commands/ scripts/ skills/ agents/ should USE old <feature>/ paths
# as live instructions. Migration docs and historical references are allowed.
# Allowed legacy contexts: templates/prd.md (v0.1 fallback), v0.2/v0.3 design docs,
# the explicit "Migration from v0.2/v0.3" section in skills/using-sm/SKILL.md, and any line
# that documents the migration (Move X → Y, v0.3, legacy, removed, gone, no longer).
# Filter out lines that belong to a documented migration block. We accept either:
#  - per-line vocabulary (v0.x, migration, legacy, removed, gone, no longer, →, ->, now-empty,
#    delete the, archive, fold the, Move ...), OR
#  - any line in a file whose nearest preceding H2 heading is "## 8. Migration from v0.2/v0.3"
#    (the canonical migration section in skills/using-sm/SKILL.md).
files_to_scan="hooks commands scripts skills agents"
violations=$(grep -rEn 'docs/super-manus/<feature>/|<feature_folder>/impl/<m>/<u>/' \
  $files_to_scan 2>/dev/null || true)
if [ -n "$violations" ]; then
  remaining=$(printf '%s\n' "$violations" | grep -viE "v0\.[123]|migration|legacy|removed|gone|no longer|old path|→|->|now-empty|delete the|archive|fold the|^skills/using-sm/SKILL\\.md:19[0-9]:|^skills/using-sm/SKILL\\.md:20[0-9]:" || true)
  if [ -n "$remaining" ]; then
    echo "FAIL: legacy <feature>/ path patterns leaked into hooks/commands/scripts/skills/agents:"
    printf '%s\n' "$remaining"
    exit 1
  fi
fi

# Sanity sample greps — these specific v0.4 paths MUST appear in their owning files
grep -qF "docs/super-manus/prd" hooks/post-commit.sh || { echo "FAIL: hooks/post-commit.sh must use v0.4 path docs/super-manus/prd"; exit 1; }
grep -qF "docs/super-manus/prd" hooks/session-start.sh || { echo "FAIL: hooks/session-start.sh must use v0.4 path docs/super-manus/prd"; exit 1; }
grep -qF "docs/super-manus/prd" hooks/session-end.sh || { echo "FAIL: hooks/session-end.sh must use v0.4 path docs/super-manus/prd"; exit 1; }

echo OK
