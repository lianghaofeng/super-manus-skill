#!/usr/bin/env bash
# Tests the impl-architect agent definition (agents/impl-architect.md).
# This agent is spawned by /super-manus:impl after the orchestrator's drift check
# passes; it owns drafting `${update_dir}/tasks/p<n>_impl.md` (the four-section
# phase plan) and the senior implementation-planner persona.

set -euo pipefail
cd "$(dirname "$0")/.."
F=agents/impl-architect.md
[ -f "$F" ] || { echo "FAIL: missing agent definition agents/impl-architect.md"; exit 1; }

# Frontmatter — name must match the subagent_type the orchestrator spawns
grep -qE "^name: impl-architect$" "$F" || { echo "FAIL: frontmatter 'name' must equal 'impl-architect'"; exit 1; }
grep -qE "^description:" "$F" || { echo "FAIL: frontmatter 'description' is required"; exit 1; }
grep -qE "^tools:" "$F" || { echo "FAIL: frontmatter must declare 'tools' (Read/Write/Edit/Glob/Grep/Bash at minimum)"; exit 1; }

# Persona: senior implementation planner (or similar)
grep -qiE "implementation planner|implementation-planning|senior implementation" "$F" || { echo "FAIL: persona must be an implementation planner"; exit 1; }

# Documents the ten inputs the orchestrator passes
for input in project_root module update_dir phase_number phase_name module_prd_path task_plan_path findings_path progress_path lsp_available; do
  grep -qF "$input" "$F" || { echo "FAIL: agent must document input '$input'"; exit 1; }
done

# Deliverable: writes ${update_dir}/tasks/p<n>_impl.md (NOT chat)
grep -qF "tasks/p" "$F" || { echo "FAIL: must specify the tasks/p<n>_impl.md write target"; exit 1; }
grep -qF "_impl.md" "$F" || { echo "FAIL: must specify the p<n>_impl.md filename pattern"; exit 1; }
grep -qiE "do NOT print|not print to chat|do not print" "$F" || { echo "FAIL: must explicitly forbid printing the file to chat"; exit 1; }

# Four exact H2 section names — Objective / Approach / Files touched / Verification
for h in "## Objective" "## Approach" "## Files touched" "## Verification"; do
  grep -qF "$h" "$F" || { echo "FAIL: agent must document section '$h'"; exit 1; }
done

# Drift check protocol references — LSP, double-source, LSP-unavailable fallback
grep -qF "Drift check protocol" "$F" || { echo "FAIL: must reference the using-sm Drift check protocol"; exit 1; }
grep -qF "LSP" "$F" || { echo "FAIL: must mention LSP as a structural-inference primary tool"; exit 1; }
grep -qiE "double-source|cross-check|both LSP and" "$F" || { echo "FAIL: must articulate the double-source / cross-check rule"; exit 1; }
grep -qiE "LSP unavailable|LSP not available|no language server" "$F" || { echo "FAIL: must specify the LSP-unavailable fallback path"; exit 1; }

# Idempotency: do not overwrite filled phase plans
grep -qiE "idempotent|idempotency|do NOT overwrite|already drafted" "$F" || { echo "FAIL: must specify idempotency — don't overwrite filled phase plans"; exit 1; }

# Budget: ≤5 LSP, ≤10 grep/Read
grep -qiE "≤5 LSP|5 LSP" "$F" || { echo "FAIL: must mention ≤5 LSP call ceiling"; exit 1; }
grep -qiE "≤10|10 grep|grep / Read" "$F" || { echo "FAIL: must mention ≤10 grep/Read ceiling"; exit 1; }
grep -qiF "budget" "$F" || { echo "FAIL: must specify a source-reading budget"; exit 1; }

# "No code in the phase plan" rule
grep -qiE "no code in the phase plan|do not write code|No code\b|not write code" "$F" || { echo "FAIL: must include 'no code in the phase plan' rule"; exit 1; }

# Returns ONE summary line
grep -qiE "summary line|one[- ]line summary|one summary line|return.*one summary" "$F" || { echo "FAIL: must specify the agent returns ONE summary line"; exit 1; }
grep -qiE "drafted.*p<n>_impl|drafted p" "$F" || { echo "FAIL: must specify the 'drafted p<n>_impl.md' summary form"; exit 1; }

# (audit) policy — single-source / no bulk
grep -qiE "single.source|do NOT bulk-mark|bulk[ -]mark" "$F" || { echo "FAIL: must restrict (audit) markers (single-source only, no bulk)"; exit 1; }

echo OK
