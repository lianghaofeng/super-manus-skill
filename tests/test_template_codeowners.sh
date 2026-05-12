#!/usr/bin/env bash
# Tests templates/codeowners.example — v0.9.7 R14: ready-to-adapt CODEOWNERS
# template documenting super-manus path conventions + GitHub CODEOWNERS quirks.

set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/codeowners.example
[ -f "$F" ] || { echo "FAIL: missing $F"; exit 1; }

# The three path patterns each module MUST own (PRD + spec + impl tree).
grep -qE "docs/super-manus/prd/[a-z_-]+\.md" "$F" \
  || { echo "FAIL: template must show prd/<module>.md path example"; exit 1; }
grep -qE "docs/super-manus/prd/[a-z_-]+\.spec\.md" "$F" \
  || { echo "FAIL: template must show prd/<module>.spec.md path example"; exit 1; }
grep -qE "docs/super-manus/impl/[a-z_-]+/\*\*" "$F" \
  || { echo "FAIL: template must show impl/<module>/** path example"; exit 1; }

# Cross-module files must be present (these require multi-team review)
grep -qF "docs/super-manus/prd/_index.md" "$F" \
  || { echo "FAIL: template must include _index.md as a cross-module file"; exit 1; }
grep -qF "docs/super-manus/roadmap.md" "$F" \
  || { echo "FAIL: template must include roadmap.md as a cross-module file"; exit 1; }
grep -qF "docs/super-manus/drift_log.md" "$F" \
  || { echo "FAIL: template must include drift_log.md as a cross-module file"; exit 1; }

# Cross-module rows must list more than one team (cross-module reviewing is the
# whole point of including them in CODEOWNERS).
grep -qE "drift_log\.md.*@.*@" "$F" \
  || { echo "FAIL: drift_log.md rule must list at least two teams (cross-module review)"; exit 1; }

# GitHub CODEOWNERS quirks — at least 3 of the 6 sharp edges must be called out
# in inline comments so users don't burn time debugging them. We're flexible on
# which 3, but the file should warn.
quirks_count=0
grep -qiE "gitignore.style|gitignore style|gitignore-style" "$F" && quirks_count=$((quirks_count + 1))
grep -qiE "same.org|same organization|same GitHub org" "$F" && quirks_count=$((quirks_count + 1))
grep -qiE "last match.*win|order matters|last.matching" "$F" && quirks_count=$((quirks_count + 1))
grep -qiE "3MB|3000 lines|file size limit|max.*size|silently ignored" "$F" && quirks_count=$((quirks_count + 1))
grep -qiE "@username.*personal|personal repo|personal fork|fork.*username" "$F" && quirks_count=$((quirks_count + 1))
grep -qiE "no inline comment|inline comment.*username|comments.*after a rule" "$F" && quirks_count=$((quirks_count + 1))
[ "$quirks_count" -ge 3 ] \
  || { echo "FAIL: template must document at least 3 GitHub CODEOWNERS quirks (found $quirks_count); see R14 design doc"; exit 1; }

# Convention reference — at least one inline comment must reference super-manus
# per-module convention so the user can extend it themselves.
grep -qiE "module|per-module|per module" "$F" \
  || { echo "FAIL: template must reference the per-module convention"; exit 1; }

# Placeholder pattern — @your-org/<team> should appear so users know what to replace
grep -qE "@your-org/" "$F" \
  || { echo "FAIL: template must use @your-org/<team> placeholders so users know what to edit"; exit 1; }

# Auto-install warning: docs must say it's NOT auto-installed
grep -qiE "not auto.install|manual.*copy|copy this file|copy.*to \.github" "$F" \
  || { echo "FAIL: template must instruct user how to copy + that it's not auto-installed"; exit 1; }

echo OK
