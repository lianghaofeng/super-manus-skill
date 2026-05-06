#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=commands/impl.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }

# Frontmatter
grep -qF "description:" "$F" || { echo "FAIL: missing frontmatter description"; exit 1; }

# Resolves active feature + active update via sm_active_update
grep -qF ".super-manus/active" "$F" || { echo "FAIL: must read .super-manus/active"; exit 1; }
grep -qF "sm_active_update" "$F" || { echo "FAIL: must use sm_active_update helper to resolve active update"; exit 1; }

# Operates on v0.2 layout (per-update task_plan.md, tasks/p<n>_impl.md inside the update folder)
grep -qF "task_plan.md" "$F" || { echo "FAIL: must reference task_plan.md (per-update)"; exit 1; }
grep -qF "tasks/p" "$F" || { echo "FAIL: must reference tasks/p<n>_impl.md path"; exit 1; }

# Drift detection: must read prd/<module>.md and append a prd_drift.md row on conflict
grep -qF "prd/<module>.md" "$F" || { echo "FAIL: must read per-module PRD"; exit 1; }
grep -qF "prd_drift.md" "$F" || { echo "FAIL: must reference prd_drift.md for drift logging"; exit 1; }
grep -qiF "drift" "$F" || { echo "FAIL: must call out drift detection responsibility"; exit 1; }

# Must NOT silently update PRD — drift always logged, user-decided
grep -qiF "/super-manus:prd-update" "$F" || { echo "FAIL: must point user at prd-update for resolution"; exit 1; }

# Must auto-find next pending phase
grep -qiF "pending" "$F" || { echo "FAIL: must mention pending phase auto-selection"; exit 1; }

# Replaces /phase: handles seeding tasks/p<n>_impl.md when missing
grep -qF "phase_plan.md" "$F" || { echo "FAIL: must use phase_plan.md template to seed missing impl plan"; exit 1; }

# Argument flexibility: target may be omitted, an update name, or a module name
grep -qiF "target" "$F" || { echo "FAIL: must document optional target argument"; exit 1; }

# Must NOT touch progress.md by hand (hook-managed)
grep -qiF "progress.md" "$F" || { echo "FAIL: must mention progress.md (specifically: not to hand-edit)"; exit 1; }

# Drift check uses the using-sm Drift check protocol (LSP + grep cooperation)
grep -qF "Drift check protocol" "$F" || { echo "FAIL: impl.md must reference using-sm's Drift check protocol"; exit 1; }
grep -qF "LSP" "$F" || { echo "FAIL: impl.md drift check must invoke LSP, not just text scan"; exit 1; }
grep -qiE "double-source|cross-check|both LSP and" "$F" || { echo "FAIL: impl.md must keep the double-source rule visible"; exit 1; }

echo OK
