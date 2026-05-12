#!/usr/bin/env bash
# Tests sm-start.sh's v0.9.7 R15 migration: drift_log.md 4-col → 5-col with
# Author cell inserted between Date and Module, `unknown` injected for legacy
# data rows. Idempotent on re-run.

set -euo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Set up a fake project with the legacy 4-column drift_log.md
mkdir -p "$TMP/docs/super-manus/prd" "$TMP/docs/super-manus/impl"
cat > "$TMP/docs/super-manus/prd/_index.md" <<'EOF'
# Project (placeholder)

## Problem
(placeholder)

## Audience
(placeholder)

## Success metrics
(placeholder)

## Demo
(placeholder)

## Must
(placeholder)

## Not doing
(placeholder)

## Modules
- api — backend (placeholder)

## Data flow overview
(placeholder)
EOF

cat > "$TMP/docs/super-manus/drift_log.md" <<'EOF'
<!-- legacy 4-column drift_log header comment -->
# Drift log

## PRD drift

| Date | Module | Conflict | Resolution |
| --- | --- | --- | --- |
| 2026-05-01 | api | bullet X declared but not in commits | pending |
| 2026-05-02 | api | capability Y shipped but not in PRD | acknowledged |

## Spec drift

| Date | Module | Conflict | Resolution |
| --- | --- | --- | --- |
| 2026-05-03 | api | missing api.spec.md | pending |
EOF

# Need roadmap.md present (sm-start's idempotent short-circuit checks
# prd/_index.md presence; layout requires roadmap.md or sm-start will
# re-create it from template, which is fine for this test)

# Run sm-start in this dir; it must perform the R15 migration and exit 0.
# CLAUDE_PLUGIN_ROOT points at the plugin root (current dir).
(cd "$TMP" && CLAUDE_PLUGIN_ROOT="$PWD/../../$(basename "$(cd .. && pwd)")" bash -c 'CLAUDE_PLUGIN_ROOT="$OLDPWD" /dev/null' 2>/dev/null || true)
# Simpler: just invoke sm-start directly with explicit CLAUDE_PLUGIN_ROOT.
PLUGIN_ROOT="$(pwd)"
(cd "$TMP" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/scripts/sm-start.sh" >/dev/null) \
  || { echo "FAIL: sm-start.sh exited non-zero on R15 migration"; exit 1; }

# Verify: drift_log.md is now 5-column
F="$TMP/docs/super-manus/drift_log.md"
[ -f "$F" ] || { echo "FAIL: drift_log.md missing after migration"; exit 1; }

# 5-column header must appear under BOTH H2 sections
header_count=$(grep -cF "| Date | Author | Module | Conflict | Resolution |" "$F" || true)
[ "$header_count" -ge 2 ] \
  || { echo "FAIL: drift_log.md must have 5-column header under both H2 sections after migration (found $header_count, need >=2)"; cat "$F"; exit 1; }

# 5-column separator
sep_count=$(grep -cF "| --- | --- | --- | --- | --- |" "$F" || true)
[ "$sep_count" -ge 2 ] \
  || { echo "FAIL: drift_log.md must have 5-column separator under both H2 sections after migration (found $sep_count, need >=2)"; cat "$F"; exit 1; }

# Negative: old 4-col schema must be gone
grep -qF "| Date | Module | Conflict | Resolution |" "$F" \
  && { echo "FAIL: old 4-column header still present after migration"; cat "$F"; exit 1; } || true

# All three legacy data rows must now have `unknown` as the Author cell
grep -qF "| 2026-05-01 | unknown | api | bullet X declared but not in commits | pending |" "$F" \
  || { echo "FAIL: legacy data row 1 not migrated to 5-col with 'unknown' Author"; cat "$F"; exit 1; }
grep -qF "| 2026-05-02 | unknown | api | capability Y shipped but not in PRD | acknowledged |" "$F" \
  || { echo "FAIL: legacy data row 2 not migrated to 5-col with 'unknown' Author"; cat "$F"; exit 1; }
grep -qF "| 2026-05-03 | unknown | api | missing api.spec.md | pending |" "$F" \
  || { echo "FAIL: spec-drift legacy data row not migrated to 5-col with 'unknown' Author"; cat "$F"; exit 1; }

# Idempotency: second invocation must NOT mangle the file further
SNAPSHOT_BEFORE=$(cat "$F")
(cd "$TMP" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/scripts/sm-start.sh" >/dev/null) \
  || { echo "FAIL: sm-start.sh second invocation exited non-zero"; exit 1; }
SNAPSHOT_AFTER=$(cat "$F")
[ "$SNAPSHOT_BEFORE" = "$SNAPSHOT_AFTER" ] \
  || { echo "FAIL: R15 migration is not idempotent — second sm-start invocation modified drift_log.md"; diff <(echo "$SNAPSHOT_BEFORE") <(echo "$SNAPSHOT_AFTER"); exit 1; }

echo OK
