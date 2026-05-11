#!/usr/bin/env bash
# Tests the impl-code-writer agent definition (agents/impl-code-writer.md).
# Spawned by /super-manus:impl step 3 — writes implementation code to make red
# phase tests + touched e2e tests green. Read-only on test files: persona forbids
# editing anything under update_dir/tests/ or docs/super-manus/e2e/. The orchestrator
# additionally hashes test files before/after to detect tamper.

set -euo pipefail
cd "$(dirname "$0")/.."
F=agents/impl-code-writer.md
[ -f "$F" ] || { echo "FAIL: missing agent definition agents/impl-code-writer.md"; exit 1; }

# Frontmatter — name must match the subagent_type the orchestrator spawns
grep -qE "^name: impl-code-writer$" "$F" || { echo "FAIL: frontmatter 'name' must equal 'impl-code-writer'"; exit 1; }
grep -qE "^description:" "$F" || { echo "FAIL: frontmatter 'description' is required"; exit 1; }
grep -qE "^tools:" "$F" || { echo "FAIL: frontmatter must declare 'tools'"; exit 1; }

# v0.8.0/v0.8.2: writer-tier routing. Code-writer is constrained by red tests
# (green = success). v0.8.2 switched `model: opus` → `model: inherit` so a
# Sonnet main thread runs writers on Sonnet automatically, and
# CLAUDE_CODE_SUBAGENT_MODEL env var works as native override. See
# docs/design-v0.8.md §4 + §9.
grep -qE "^model: inherit$" "$F" || { echo "FAIL: writer-tier agents must use 'model: inherit' (v0.8.2)"; exit 1; }
grep -qE "^effort: high$" "$F" || { echo "FAIL: frontmatter must declare 'effort: high' (writer-tier default; CLAUDE_CODE_EFFORT_LEVEL overrides if set)"; exit 1; }

# Tools whitelist: Read, Write, Edit, Glob, Grep, Bash. Edit IS allowed (code-writer
# edits source code) but the persona forbids editing tests/ and e2e/.
for tool in Read Write Edit Glob Grep Bash; do
  grep -qE "^tools:.*\b${tool}\b" "$F" || { echo "FAIL: frontmatter 'tools' must list ${tool}"; exit 1; }
done

# Hard rule: must NOT edit test files. The cheat-prevention boundary is write-permission.
grep -qiE "MUST NOT|must not" "$F" || { echo "FAIL: must contain a 'MUST NOT' (or 'must not') hard rule on test edits"; exit 1; }
grep -qF "tests/" "$F" || { echo "FAIL: must reference the tests/ directory in the write-barrier rule"; exit 1; }
grep -qF "e2e/" "$F" || { echo "FAIL: must reference the e2e/ directory in the write-barrier rule"; exit 1; }

# Escalation path on suspect test: append a row to findings.md ## Errors.
grep -qF "findings.md" "$F" || { echo "FAIL: escalation path must reference findings.md"; exit 1; }
grep -qF "## Errors" "$F" || { echo "FAIL: escalation path must reference findings.md ## Errors"; exit 1; }

# Mentions phase tests + e2e tests in inputs / read scope.
grep -qF "phase_tests_glob" "$F" || { echo "FAIL: must reference phase_tests_glob input"; exit 1; }
grep -qF "e2e_tests_glob" "$F" || { echo "FAIL: must reference e2e_tests_glob input"; exit 1; }

# Documents the eleven inputs the orchestrator passes (per design v0.5 §3 +
# commands/impl.md step 3).
for input in project_root module update_dir phase_number phase_name module_prd_path \
             task_plan_path phase_plan_path phase_tests_glob e2e_tests_glob lsp_available; do
  grep -qF "$input" "$F" || { echo "FAIL: agent must document input '$input'"; exit 1; }
done

# Karpathy guidelines reference.
grep -qF "karpathy-guidelines" "$F" || { echo "FAIL: must reference karpathy-guidelines"; exit 1; }

# Returns ONE summary line: "all N phase tests + M e2e tests pass" (or close).
grep -qiE "all .*tests pass|all N phase tests|all .* phase tests.*e2e tests pass" "$F" \
  || { echo "FAIL: return summary must say 'all N phase tests + M e2e tests pass' (or sufficiently similar)"; exit 1; }

# Hash check is mechanical (orchestrator-side); the agent must KNOW it exists so the
# persona's write-barrier discipline isn't merely advisory.
grep -qiE "hash|SHA-256|sha256" "$F" || { echo "FAIL: must mention orchestrator's hash check (the mechanical enforcement of the write barrier)"; exit 1; }

# === v0.9.4 R4: commit hygiene + staging whitelist ========================
# Code-writer must run `git status --porcelain` before commit, stage only files
# from `## Files touched`, and return OUT_OF_SCOPE_DIRTY if the tree contains
# dirty files outside scope. `git add .` / `git add -A` are explicitly banned.

grep -qF "git status --porcelain" "$F" \
  || { echo "FAIL: v0.9.4 R4 must require 'git status --porcelain' before commit"; exit 1; }
grep -qF "OUT_OF_SCOPE_DIRTY" "$F" \
  || { echo "FAIL: v0.9.4 R4 must document the OUT_OF_SCOPE_DIRTY return contract"; exit 1; }
grep -qE 'git add \.|git add -A' "$F" \
  || { echo "FAIL: v0.9.4 R4 must explicitly ban broad git-add commands (git add . / git add -A)"; exit 1; }
grep -qF "## Files touched" "$F" \
  || { echo "FAIL: v0.9.4 R4 must reference '## Files touched' as the staging whitelist"; exit 1; }
grep -qiE "git add <specific-path>|git add <file>|per file" "$F" \
  || { echo "FAIL: v0.9.4 R4 must require per-file 'git add <specific-path>' staging"; exit 1; }

# === v0.9.5 R7: <module>.spec.md is read-only =============================
# The per-module engineering reference is target state — code-writer must NOT
# edit it during a phase (back-channel drift). The persona lists it in the
# write barrier, alongside tests/ and e2e/.

grep -qF "<module>.spec.md" "$F" \
  || { echo "FAIL: v0.9.5 R7 must include <module>.spec.md in the write-barrier list"; exit 1; }
grep -qiE "spec.md.*back-channel|back-channel.*spec|long-lived target|target state" "$F" \
  || { echo "FAIL: v0.9.5 R7 must explain WHY editing spec.md is forbidden (back-channel drift / target state)"; exit 1; }
# Escalation path: if spec is wrong, user runs /super-manus:spec-update separately
grep -qF "/super-manus:spec-update" "$F" \
  || { echo "FAIL: v0.9.5 R7 must redirect spec changes to /super-manus:spec-update (not in-phase edits)"; exit 1; }

echo OK
