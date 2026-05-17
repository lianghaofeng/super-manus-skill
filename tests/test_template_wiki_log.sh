#!/usr/bin/env bash
# Tests templates/wiki_log.md — v0.9.8 R16 append-only wiki event log.
# Seeded by /super-manus:start into docs/super-manus/wiki/_log.md.
# Sole provenance record for promote / promote-rejected / lint events.

set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/wiki_log.md
[ -f "$F" ] || { echo "FAIL: missing $F"; exit 1; }

# H1 — stable schema heading
grep -q "^# Wiki log" "$F" || { echo "FAIL: missing '# Wiki log' H1 title"; exit 1; }

# Header comment must declare append-only semantics — this is load-bearing
# (orchestrator's promote gate ONLY appends; old entries must never be
# rewritten because they're the audit trail).
grep -qiE "append-only|append only" "$F" \
  || { echo "FAIL: header must declare append-only semantics"; exit 1; }

# Sole-provenance-record property — explicit so future contributors don't
# re-introduce source-side annotation (rejected design in v0.9.8 R17
# simplification).
grep -qiE "sole provenance|only provenance|no back-annotation|no annotation" "$F" \
  || { echo "FAIL: header must call out that this log is the sole provenance record (no source-side annotation on findings.md)"; exit 1; }

# Entry prefix format must be documented verbatim — tools and lint summaries
# parse it. Mismatch = silent runtime break.
grep -qF "## [YYYY-MM-DD] <event> | <details>" "$F" \
  || { echo "FAIL: header must document the entry prefix format verbatim: '## [YYYY-MM-DD] <event> | <details>'"; exit 1; }

# Grep parseability hint — load-bearing for the "recent activity" query.
# Verify both 'grep' and the literal "## [" prefix string are present in the
# header (avoid escaping headaches by checking a substring of the example).
grep -qF "grep" "$F" || { echo "FAIL: header should mention 'grep' as the canonical recent-activity query tool"; exit 1; }
grep -qF "wiki/_log.md | tail" "$F" \
  || { echo "FAIL: header should document the canonical recent-activity query example (grep ... wiki/_log.md | tail)"; exit 1; }

# Event types must be enumerated so future contributors know which strings
# are valid event names (matches what orchestrator/wiki-lint actually emit).
grep -qF "promote" "$F" || { echo "FAIL: header must enumerate 'promote' event type"; exit 1; }
grep -qF "promote-rejected" "$F" || { echo "FAIL: header must enumerate 'promote-rejected' event type"; exit 1; }
grep -qF "lint" "$F" || { echo "FAIL: header must enumerate 'lint' event type"; exit 1; }

# Skeleton must be EMPTY of event entries (first promote/lint creates one).
h2_count=$(grep -cE "^## \[" "$F" || true)
[ "$h2_count" = "0" ] || { echo "FAIL: skeleton must have zero event entries (got $h2_count); first promote/lint creates one"; exit 1; }

# Sanity: small skeleton.
line_count=$(wc -l < "$F")
[ "$line_count" -lt 80 ] || { echo "FAIL: skeleton is unexpectedly large ($line_count lines)"; exit 1; }

echo OK
