#!/usr/bin/env bash
# Tests commands/wiki-lint.md — v0.9.8 R19 standalone wiki-health pass.
# Same scan that runs as end-of-update drift gate Pass 4, invokable on demand.
# Non-blocking: surfaces counts to user, doesn't gate anything.

set -euo pipefail
cd "$(dirname "$0")/.."
F=commands/wiki-lint.md
[ -f "$F" ] || { echo "FAIL: missing $F"; exit 1; }

# Frontmatter — description present
grep -qE "^description:" "$F" \
  || { echo "FAIL: $F must declare frontmatter description"; exit 1; }

# Must spawn impl-reviewer with mode=wiki-lint (the new mode added in R19)
grep -qF "mode=wiki-lint" "$F" \
  || { echo "FAIL: v0.9.8 R19 — wiki-lint command must spawn impl-reviewer with mode=wiki-lint"; exit 1; }
grep -qF "impl-reviewer" "$F" \
  || { echo "FAIL: wiki-lint command must spawn the impl-reviewer agent (subagent_type)"; exit 1; }

# Subagent type uses the plugin namespace
grep -qF "super-manus:impl-reviewer" "$F" \
  || { echo "FAIL: wiki-lint command must spawn impl-reviewer via the full subagent_type=\"super-manus:impl-reviewer\""; exit 1; }

# Output sink: wiki/_log.md
grep -qF "wiki/_log.md" "$F" \
  || { echo "FAIL: wiki-lint command must declare wiki/_log.md as the output sink"; exit 1; }

# Five checks must all be mentioned (so the user knows what wiki-lint covers)
for check in "[Cc]ontradiction" "[Ss]tale" "[Oo]rphan" "[Gg]ap" "[Cc]ross-ref"; do
  grep -qE "$check" "$F" \
    || { echo "FAIL: v0.9.8 R19 wiki-lint command must surface the '$check' check in user-facing summary"; exit 1; }
done

# Non-blocking property called out
grep -qiE "non.blocking|advisory|does not gate|doesn.t (block|gate)" "$F" \
  || { echo "FAIL: v0.9.8 R19 wiki-lint command must declare itself non-blocking / advisory"; exit 1; }

# Precondition: wiki/ absent → skip gracefully
grep -qiE "wiki/ (is )?absent|missing wiki|no wiki/ directory" "$F" \
  || { echo "FAIL: wiki-lint command must handle the wiki/ absent precondition (pre-v0.9.8 project) gracefully"; exit 1; }

# Per-agent model override resolution (same pattern as /super-manus:impl)
grep -qF "sm_agent_model" "$F" \
  || { echo "FAIL: wiki-lint command must support per-agent model override via sm_agent_model (consistent with /super-manus:impl)"; exit 1; }

# Cross-reference to /super-manus:impl + /super-manus:impl-all (same scan as Pass 4 of drift gate)
grep -qiE "Pass 4|end-of-update drift gate|same scan|drift gate.{0,30}Pass 4" "$F" \
  || { echo "FAIL: wiki-lint command must cross-reference end-of-update drift gate Pass 4 (it's the same scan, just invokable standalone)"; exit 1; }

# WIKI_LINT_COMPLETE verdict surfacing
grep -qF "WIKI_LINT_COMPLETE" "$F" \
  || { echo "FAIL: wiki-lint command must reference the WIKI_LINT_COMPLETE verdict the reviewer returns"; exit 1; }

# Documents what to do with findings (manual edit / wiki-promote next phase / wiki-archive)
grep -qiE "manual edit|edit.{0,20}wiki|human-curated|wiki maintenance" "$F" \
  || { echo "FAIL: wiki-lint command must explain that wiki maintenance is human-curated (no auto-fix); user reads _log.md and acts manually"; exit 1; }

echo OK
