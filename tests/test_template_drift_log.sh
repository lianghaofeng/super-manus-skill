#!/usr/bin/env bash
# Tests templates/drift_log.md — v0.9.5 R10 rename from prd_drift.md; v0.9.7 R15
# adds Author column (4 → 5). Two H2 sections (## PRD drift / ## Spec drift),
# each carrying the same 5-column schema. The append-only / Resolution-only-
# mutable invariant is preserved verbatim from prd_drift.md.

set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/drift_log.md
[ -f "$F" ] || { echo "FAIL: missing $F"; exit 1; }

# H1 — single, stable
grep -q "^# Drift log" "$F" || { echo "FAIL: missing '# Drift log' H1 title"; exit 1; }
# Negative regression — old H1 must be gone
grep -q "^# PRD drift log" "$F" \
  && { echo "FAIL: v0.9.5 R10 must drop the old '# PRD drift log' H1 (renamed to '# Drift log')"; exit 1; } || true

# Two H2 sections — exact match
grep -qF "## PRD drift" "$F" || { echo "FAIL: must declare ## PRD drift H2 section"; exit 1; }
grep -qF "## Spec drift" "$F" || { echo "FAIL: v0.9.5 R10 must declare ## Spec drift H2 section"; exit 1; }

# 5-column schema (v0.9.7 R15 — Author inserted between Date and Module).
# Schema appears under each H2 section — at least 2 occurrences expected.
header_count=$(grep -cF "| Date | Author | Module | Conflict | Resolution |" "$F" || true)
[ "$header_count" -ge 2 ] \
  || { echo "FAIL: 5-column schema header (Date | Author | Module | Conflict | Resolution) must appear under each H2 section (found $header_count, need >=2) — v0.9.7 R15 multi-author baseline"; exit 1; }

# Negative regression — old 4-column schema must not survive
grep -qF "| Date | Module | Conflict | Resolution |" "$F" \
  && { echo "FAIL: old 4-column schema (Date | Module | Conflict | Resolution) must be removed in v0.9.7 R15 — replaced by 5-column with Author"; exit 1; } || true

# Author cell sourcing rule must be documented in header
grep -qF "git config user.name" "$F" \
  || { echo "FAIL: header must document that Author cell is sourced from 'git config user.name' (v0.9.7 R15)"; exit 1; }
grep -qiE "unknown" "$F" \
  || { echo "FAIL: header must mention 'unknown' as the fallback when git config user.name is unset"; exit 1; }

# Header comment must declare the file as append-only
grep -qi "append" "$F" || { echo "FAIL: header should call out append-only semantics"; exit 1; }

# Header comment must declare both drift kinds (PRD + spec)
grep -qiE "PRD.*spec|spec.*PRD|both PRD" "$F" \
  || { echo "FAIL: header must explain the two H2 sections cover both PRD and spec drift"; exit 1; }

# Header comment must reference both update commands as resolution paths
grep -qF "/super-manus:prd-update" "$F" \
  || { echo "FAIL: header should reference /super-manus:prd-update as the PRD-side resolution path"; exit 1; }
grep -qF "/super-manus:spec-update" "$F" \
  || { echo "FAIL: header should reference /super-manus:spec-update as the spec-side resolution path"; exit 1; }

# Stable headings clause
grep -qiE "Headings are stable|exact match" "$F" \
  || { echo "FAIL: header should declare headings stable (parsed by hooks/scripts/agents)"; exit 1; }

echo OK
