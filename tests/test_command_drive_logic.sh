#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=commands/drive.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }

# Frontmatter
grep -qF "description:" "$F" || { echo "FAIL: missing frontmatter description"; exit 1; }

# v0.4: must NOT reference .super-manus/active (state file is gone).
grep -qF ".super-manus/active" "$F" && { echo "FAIL: drive.md must NOT reference .super-manus/active in v0.4"; exit 1; } || true

# Reads the project-global super-manus state
grep -qF "docs/super-manus/prd/" "$F" || { echo "FAIL: must reference docs/super-manus/prd/ as the project-global PRD root"; exit 1; }
grep -qF "prd/_index.md" "$F" || { echo "FAIL: must read prd/_index.md"; exit 1; }
grep -qF "roadmap.md" "$F" || { echo "FAIL: must read roadmap.md"; exit 1; }
grep -qF "drift_log.md" "$F" || { echo "FAIL: must read drift_log.md (v0.9.5 R10 — renamed from prd_drift.md)"; exit 1; }
# v0.9.5 R10: must distinguish PRD drift from spec drift in dispatch decisions
grep -qF "## PRD drift" "$F" || { echo "FAIL: must reference drift_log.md ## PRD drift section in dispatch logic"; exit 1; }
grep -qF "## Spec drift" "$F" || { echo "FAIL: must reference drift_log.md ## Spec drift section in dispatch logic"; exit 1; }

# Active update resolution must use sm_active_update (no .super-manus/active in v0.4)
grep -qF "sm_active_update" "$F" || { echo "FAIL: must use sm_active_update helper to resolve the active update (v0.4)"; exit 1; }

# Must dispatch to the right next-step command based on state
# v0.9.5 R8: spec-update added; R9: reverse-prd-spec replaces reverse-prd
for cmd in "/super-manus:brainstorm" "/super-manus:sync" "/super-manus:prd-update" "/super-manus:spec-update" "/super-manus:impl" "/super-manus:start"; do
  grep -qF "$cmd" "$F" || { echo "FAIL: must mention dispatch target $cmd"; exit 1; }
done
# Negative regression — must not invoke the renamed-out command
grep -qF "/super-manus:reverse-prd " "$F" \
  && { echo "FAIL: must NOT reference legacy /super-manus:reverse-prd (renamed to /super-manus:reverse-prd-spec in v0.9.5 R9)"; exit 1; } || true

# Must include drift-scan responsibility
grep -qiF "drift" "$F" || { echo "FAIL: must call out drift scan"; exit 1; }

# Must announce decision + reason in one line before acting (auto-mode friendly)
grep -qiF "decision" "$F" || { echo "FAIL: must announce a decision before acting"; exit 1; }

# Auto-mode: drive should execute, not just plan, when an unambiguous next step exists
grep -qiF "execute" "$F" || { echo "FAIL: must mention executing the chosen next step"; exit 1; }

echo OK
