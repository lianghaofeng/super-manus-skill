#!/usr/bin/env bash
# Tests .gitattributes — v0.9.7 R13: `merge=union` on append-only ledgers
# (drift_log.md + roadmap.md), and NOT on PRD/spec structured documents.

set -euo pipefail
cd "$(dirname "$0")/.."
F=.gitattributes
[ -f "$F" ] || { echo "FAIL: missing $F"; exit 1; }

# Positive: both append-only ledgers must have merge=union
grep -qF "docs/super-manus/drift_log.md merge=union" "$F" \
  || { echo "FAIL: .gitattributes must declare 'docs/super-manus/drift_log.md merge=union'"; exit 1; }
grep -qF "docs/super-manus/roadmap.md merge=union" "$F" \
  || { echo "FAIL: .gitattributes must declare 'docs/super-manus/roadmap.md merge=union'"; exit 1; }

# Negative regression: PRD / spec files must NEVER get merge=union (would cause
# silent merge of contradictory edits to the same ## Quality bar bullet).
# Match the whole rule line, not just the substring — a comment mentioning the
# anti-pattern is allowed (and in fact present in the header).
grep -E "^[^#]*prd/.*\.md\s+merge=union" "$F" \
  && { echo "FAIL: .gitattributes must NOT apply merge=union to any prd/*.md path (R13: PRD files are structured documents, union would silently merge contradictory edits)"; exit 1; } || true
grep -E "^[^#]*prd/.*\.spec\.md\s+merge=union" "$F" \
  && { echo "FAIL: .gitattributes must NOT apply merge=union to any prd/*.spec.md path (R13: spec files are structured documents)"; exit 1; } || true

# The rationale comment must mention the design doc so future contributors
# don't "fix" perceived PRD merge friction by adding union to PRD paths.
grep -qF "design-v0.9.7.md" "$F" \
  || { echo "FAIL: .gitattributes header should reference docs/design-v0.9.7.md R13 for the rationale"; exit 1; }

# Must call out the structured-document warning by name so the negative-regression
# rule is documented inline, not only in the design doc.
grep -qiE "structured document|silently keep|contradictor" "$F" \
  || { echo "FAIL: .gitattributes header should warn that union on structured documents silently keeps contradictory edits"; exit 1; }

echo OK
