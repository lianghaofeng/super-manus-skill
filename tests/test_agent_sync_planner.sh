#!/usr/bin/env bash
# Tests the sync-planner agent definition (agents/sync-planner.md).
# This agent is spawned by /super-manus:sync to draft a 3–6 row Phases table for
# a fresh milestone-update from a PRD diff. It owns the tech-lead persona, the
# PRD-diff-led source priority, the (audit) marker policy, and the LSP/grep budget.

set -euo pipefail
cd "$(dirname "$0")/.."
F=agents/sync-planner.md
[ -f "$F" ] || { echo "FAIL: missing agent definition agents/sync-planner.md"; exit 1; }

# Frontmatter — name must match the subagent_type the orchestrator spawns
grep -qE "^name: sync-planner$" "$F" || { echo "FAIL: frontmatter 'name' must equal 'sync-planner'"; exit 1; }
grep -qE "^description:" "$F" || { echo "FAIL: frontmatter 'description' is required"; exit 1; }
grep -qE "^tools:" "$F" || { echo "FAIL: frontmatter must declare 'tools' (Read/Grep/Glob/Bash at minimum)"; exit 1; }

# v0.8.0/v0.8.2: writer-tier routing. Output is one short Phases table — narrow
# scope, structured output. v0.8.2 switched `model: opus` → `model: inherit`
# so the main-thread model flows through. See docs/design-v0.8.md §4 + §9.
grep -qE "^model: inherit$" "$F" || { echo "FAIL: writer-tier agents must use 'model: inherit' (v0.8.2)"; exit 1; }
grep -qE "^effort: high$" "$F" || { echo "FAIL: frontmatter must declare 'effort: high' (narrow-scope default; CLAUDE_CODE_EFFORT_LEVEL overrides if set)"; exit 1; }

# Persona: tech lead (or similar)
grep -qiE "tech lead|technical lead|engineering lead" "$F" || { echo "FAIL: persona must mention tech lead (or similar)"; exit 1; }

# Documents the six inputs the orchestrator passes
for input in project_root module update_name module_prd_path prd_diff lsp_available; do
  grep -qF "$input" "$F" || { echo "FAIL: agent must document input '$input'"; exit 1; }
done

# Output format: ONE markdown Phases table with the | # | Name | Status | schema
grep -qF "| # | Name | Status |" "$F" || { echo "FAIL: must specify the | # | Name | Status | table header schema"; exit 1; }
grep -qiE "markdown table" "$F" || { echo "FAIL: must specify the deliverable is a markdown table"; exit 1; }

# Phase count guidance: 3–6 phases
grep -qE "3.*6 phases|3–6 phases|3 to 6 phases|3-6 phases" "$F" || { echo "FAIL: must state the 3–6 phases count guidance"; exit 1; }

# (audit) marker policy: defined and not bulk-applied
grep -qF "(audit)" "$F" || { echo "FAIL: must document the (audit) marker"; exit 1; }
grep -qiE "do NOT bulk-mark|bulk[ -]mark" "$F" || { echo "FAIL: must restrict (audit) usage (no bulk-marking)"; exit 1; }

# Source priority — must list at least 3 of: PRD diff / module surface / code reality / cross-module
priority_hits=0
for term in "PRD diff" "module surface" "code reality" "cross-module" "Cross-module" "Existing module surface"; do
  if grep -qF "$term" "$F"; then priority_hits=$((priority_hits+1)); fi
done
[ "$priority_hits" -ge 3 ] || { echo "FAIL: must list at least 3 source-priority steps (PRD diff / module surface / code reality / cross-module), got $priority_hits"; exit 1; }

# LSP / grep budget mentioned: ≤5 LSP, ≤15 grep/Read
grep -qiE "≤5 LSP|5 LSP" "$F" || { echo "FAIL: must mention the ≤5 LSP call ceiling"; exit 1; }
grep -qiE "≤15|15 grep|15 grep / Read|grep / Read" "$F" || { echo "FAIL: must mention the ≤15 grep/Read ceiling"; exit 1; }
grep -qiF "budget" "$F" || { echo "FAIL: must specify the source-reading budget"; exit 1; }

# Returns ONE summary line — "drafted ... phases"
grep -qiE "drafted .*phases|drafted <N> phases|drafted \\\\<N\\\\> phases" "$F" || { echo "FAIL: must specify the 'drafted <N> phases' summary line"; exit 1; }
grep -qiE "summary line|one[- ]line summary|one summary line" "$F" || { echo "FAIL: must specify the summary line is ONE line"; exit 1; }

# Conservatism: do not write code, do not write files (the orchestrator handles injection)
grep -qiE "do NOT write|do not write any files|nothing else" "$F" || { echo "FAIL: must instruct the agent to NOT write files itself (orchestrator handles injection)"; exit 1; }

echo OK
