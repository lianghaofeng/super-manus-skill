#!/usr/bin/env bash
# Tests templates/wiki_index.md — v0.9.8 R16 LLM-maintained catalog skeleton.
# Seeded by /super-manus:start into docs/super-manus/wiki/_index.md.
# Regenerated from scratch by orchestrator after every accepted promote.

set -euo pipefail
cd "$(dirname "$0")/.."
F=templates/wiki_index.md
[ -f "$F" ] || { echo "FAIL: missing $F"; exit 1; }

# H1 is the load-bearing schema heading parsed by sm_load_wiki and wiki-lint.
grep -q "^# Wiki index" "$F" || { echo "FAIL: missing '# Wiki index' H1 title"; exit 1; }

# Header comment must declare LLM-maintained / auto-regenerated semantics so
# contributors don't hand-edit and have their changes overwritten.
grep -qiE "LLM-maintained|auto-regenerated|regenerated" "$F" \
  || { echo "FAIL: header must call out that this file is LLM-maintained / regenerated"; exit 1; }

# Schema documentation must mention the H2-per-topic + bulleted-rule format
# so future LLM regenerations stay consistent.
grep -qF "H2 per topic file" "$F" \
  || { echo "FAIL: header schema must document the H2-per-topic-file structure"; exit 1; }
grep -qF ".md#<anchor>" "$F" \
  || { echo "FAIL: header schema must show the anchor-link bullet format (<topic>.md#<anchor>)"; exit 1; }

# Must reference the promote gate path (where new rules come from) so a
# reader can trace any rule back to its origin.
grep -qF "/super-manus:impl" "$F" \
  || { echo "FAIL: header should reference /super-manus:impl as the promote gate"; exit 1; }
grep -qF "wiki-candidates" "$F" \
  || { echo "FAIL: header should reference reviewer's 'wiki-candidates' flag (the ingest trigger)"; exit 1; }

# Decision-tree cross-reference to CLAUDE.md (so wiki-vs-spec confusion is
# resolvable without leaving the file).
grep -qF "CLAUDE.md" "$F" \
  || { echo "FAIL: header should cross-reference CLAUDE.md for the wiki-vs-spec decision tree"; exit 1; }

# Skeleton must be EMPTY of topic sections — first promote creates them.
# Verify by counting H2 headings: should be zero (only the H1 is present).
h2_count=$(grep -cE "^## " "$F" || true)
[ "$h2_count" = "0" ] || { echo "FAIL: skeleton must have zero H2 topic sections (got $h2_count); first promote creates them"; exit 1; }

# Sanity: the file should be small (it's a skeleton, not a curated example).
# Catches the case where someone accidentally seeds a populated example.
line_count=$(wc -l < "$F")
[ "$line_count" -lt 80 ] || { echo "FAIL: skeleton is unexpectedly large ($line_count lines); should be just header comment + H1 + intro paragraph"; exit 1; }

echo OK
