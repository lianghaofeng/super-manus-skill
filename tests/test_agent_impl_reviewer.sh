#!/usr/bin/env bash
# Tests the impl-reviewer agent definition (agents/impl-reviewer.md).
# This agent is spawned by /super-manus:impl at three checkpoints (pre-test /
# pre-code / pre-close). It is READ-ONLY by tool surface (no Write, no Edit) —
# cheat-prevention boundary is preserved. Its verdict (APPROVE /
# RETURN_TO_<writer> / ESCALATE_TO_USER) drives the re-spawn loop.

set -euo pipefail
cd "$(dirname "$0")/.."
F=agents/impl-reviewer.md
[ -f "$F" ] || { echo "FAIL: missing agent definition agents/impl-reviewer.md"; exit 1; }

# Frontmatter — name must match the subagent_type the orchestrator spawns
grep -qE "^name: impl-reviewer$" "$F" || { echo "FAIL: frontmatter 'name' must equal 'impl-reviewer'"; exit 1; }
grep -qE "^description:" "$F" || { echo "FAIL: frontmatter 'description' is required"; exit 1; }
grep -qE "^tools:" "$F" || { echo "FAIL: frontmatter must declare 'tools'"; exit 1; }

# Read-only by tool surface — MUST NOT include Write or Edit (cheat-prevention)
grep -E "^tools:" "$F" | grep -qE "\bWrite\b" && { echo "FAIL: reviewer MUST NOT have Write tool (read-only by tool surface)"; exit 1; }
grep -E "^tools:" "$F" | grep -qE "\bEdit\b" && { echo "FAIL: reviewer MUST NOT have Edit tool (read-only by tool surface)"; exit 1; }
grep -E "^tools:" "$F" | grep -qE "\bRead\b" || { echo "FAIL: reviewer needs Read tool"; exit 1; }
grep -E "^tools:" "$F" | grep -qE "\bGrep\b" || { echo "FAIL: reviewer needs Grep tool"; exit 1; }
grep -E "^tools:" "$F" | grep -qE "\bGlob\b" || { echo "FAIL: reviewer needs Glob tool"; exit 1; }
grep -E "^tools:" "$F" | grep -qE "\bBash\b" || { echo "FAIL: reviewer needs Bash tool (for head -1 / type-check invocations)"; exit 1; }

# Persona — staff engineer, read-only, RETURN-by-default
grep -qiE "staff engineer|senior staff" "$F" || { echo "FAIL: persona must be staff/senior engineer"; exit 1; }
grep -qiE "read[- ]only|write nothing|do not write" "$F" || { echo "FAIL: persona must declare read-only stance"; exit 1; }
grep -qiE "default is to RETURN|APPROVE is earned" "$F" || { echo "FAIL: persona must say default is RETURN, not APPROVE"; exit 1; }

# Three modes — pre-test / pre-code / pre-close (verbatim — orchestrator passes mode=<>)
grep -qF "pre-test" "$F" || { echo "FAIL: must document pre-test mode"; exit 1; }
grep -qF "pre-code" "$F" || { echo "FAIL: must document pre-code mode"; exit 1; }
grep -qF "pre-close" "$F" || { echo "FAIL: must document pre-close mode"; exit 1; }

# Three verdict types — APPROVE / RETURN_TO_<writer> / ESCALATE_TO_USER
grep -qF "APPROVE" "$F" || { echo "FAIL: must document APPROVE verdict"; exit 1; }
grep -qF "RETURN_TO_ARCHITECT" "$F" || { echo "FAIL: must document RETURN_TO_ARCHITECT verdict"; exit 1; }
grep -qF "RETURN_TO_TEST_WRITER" "$F" || { echo "FAIL: must document RETURN_TO_TEST_WRITER verdict"; exit 1; }
grep -qF "RETURN_TO_CODE_WRITER" "$F" || { echo "FAIL: must document RETURN_TO_CODE_WRITER verdict"; exit 1; }
grep -qF "ESCALATE_TO_USER" "$F" || { echo "FAIL: must document ESCALATE_TO_USER verdict"; exit 1; }

# Verdict format — VERDICT: keyword required (orchestrator parses)
grep -qE "^VERDICT:" "$F" || grep -qF "VERDICT: APPROVE" "$F" || { echo "FAIL: verdict format must use 'VERDICT:' prefix for orchestrator parsing"; exit 1; }

# Inputs from orchestrator — at minimum mode, attempt_number, phase context
for input in mode attempt_number project_root module update_dir phase_number phase_name module_prd_path lsp_available; do
  grep -qF "$input" "$F" || { echo "FAIL: agent must document input '$input'"; exit 1; }
done

# Pre-close-specific input: code_writer_stuck flag
grep -qF "code_writer_stuck" "$F" || { echo "FAIL: must document code_writer_stuck input (pre-close mode)"; exit 1; }

# Per-mode load-bearing checks
# pre-test: real-data grounding via head -1
grep -qiE "head -1|head.*-1|jq.*'\.\[0\]'|head[[:space:]]+-1" "$F" || { echo "FAIL: pre-test mode must require real-data grounding (head -1 / jq / od)"; exit 1; }
# pre-test: (audit) markers must resolve before APPROVE
grep -qiE "\(audit\) markers (must )?(be )?resolved|unresolved.*\(audit\)" "$F" || { echo "FAIL: pre-test mode must require (audit) markers to be resolved"; exit 1; }

# pre-code: real-data fixture rule
grep -qiE "real[- ]data fixture|real file|fixtures? (must )?come from real" "$F" || { echo "FAIL: pre-code mode must require real-data fixtures"; exit 1; }
# pre-code: type-check is project-configured-only (pure A — locked in design-v0.7 §10)
grep -qiE "project[- ]configured|pyproject\.toml|tsconfig\.json" "$F" || { echo "FAIL: pre-code type-check must reference project config detection"; exit 1; }
grep -qiE "skip.*type[- ]check|no.*fallback|do not run.*py_compile|no.*forced.*strict" "$F" || { echo "FAIL: pre-code type-check must explicitly skip when project has no config (no fallback py_compile)"; exit 1; }

# pre-close: route stuck code-writer to test/architect/code per root cause
grep -qF "code_writer_stuck" "$F" || { echo "FAIL: pre-close must reference code_writer_stuck"; exit 1; }

# Karpathy reference (using-sm/SKILL.md §9)
grep -qF "using-sm/SKILL.md §9" "$F" || grep -qiE "karpathy" "$F" || { echo "FAIL: must reference using-sm §9 / karpathy guidelines"; exit 1; }

# Budget — tighter than writers (per design §2)
grep -qE "LSP calls.*≤5|≤5.*LSP|LSP.*≤ 5" "$F" || { echo "FAIL: must specify ≤5 LSP call budget per review"; exit 1; }
grep -qE "grep.*Read.*≤15|≤15.*grep|grep.*≤ 15" "$F" || { echo "FAIL: must specify ≤15 grep/Read call budget per review"; exit 1; }

# Idempotency — re-spawn awareness via attempt_number
grep -qiE "re[- ]spawn|attempt_number > 1|attempt_number = 1" "$F" || { echo "FAIL: must specify re-spawn / attempt_number behavior"; exit 1; }
grep -qiE "findings\.md ## Errors" "$F" || { echo "FAIL: must specify reading prior reviewer feedback from findings.md ## Errors"; exit 1; }

# Per-mode upstream RETURN targets (cascade authority)
# pre-code can RETURN_TO_ARCHITECT (cascade upstream)
grep -qE "pre-code.*RETURN_TO_ARCHITECT|RETURN_TO_ARCHITECT.*pre-code" "$F" \
  || grep -qiE "pre-code.*upstream|cascade" "$F" \
  || { echo "FAIL: pre-code must be able to RETURN_TO_ARCHITECT (cascade upstream)"; exit 1; }

# pre-close can RETURN to all 3 upstream writers
grep -qE "pre-close.*RETURN_TO_TEST_WRITER|RETURN_TO_TEST_WRITER" "$F" || { echo "FAIL: pre-close must be able to RETURN_TO_TEST_WRITER"; exit 1; }

# What reviewer does NOT do — prevents drift toward writer-style behavior
grep -qiE "do not write any file|do NOT write|write nothing" "$F" || { echo "FAIL: must explicitly forbid writing files"; exit 1; }

echo OK
