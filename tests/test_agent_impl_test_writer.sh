#!/usr/bin/env bash
# Tests the impl-test-writer agent definition (agents/impl-test-writer.md).
# Spawned by /super-manus:impl step 2 — writes red phase tests + e2e tests
# anchored in PRD spec (NOT in tasks/p<n>_impl.md ## Approach). Read-everything,
# write-tests-only, commits BEFORE impl-code-writer is spawned. The orchestrator
# hashes test files between this agent and impl-code-writer; tamper aborts the phase.

set -euo pipefail
cd "$(dirname "$0")/.."
F=agents/impl-test-writer.md
[ -f "$F" ] || { echo "FAIL: missing agent definition agents/impl-test-writer.md"; exit 1; }

# Frontmatter — name must match the subagent_type the orchestrator spawns
grep -qE "^name: impl-test-writer$" "$F" || { echo "FAIL: frontmatter 'name' must equal 'impl-test-writer'"; exit 1; }
grep -qE "^description:" "$F" || { echo "FAIL: frontmatter 'description' is required"; exit 1; }
grep -qE "^tools:" "$F" || { echo "FAIL: frontmatter must declare 'tools' (Read/Write/Glob/Grep/Bash; NO Edit)"; exit 1; }

# Tools whitelist: Read, Write, Glob, Grep, Bash. Must NOT list Edit (write-permission
# barrier — test-writer cannot edit; only writes new files).
for tool in Read Write Glob Grep Bash; do
  grep -qE "^tools:.*\b${tool}\b" "$F" || { echo "FAIL: frontmatter 'tools' must list ${tool}"; exit 1; }
done
if grep -qE "^tools:.*\bEdit\b" "$F"; then
  echo "FAIL: frontmatter 'tools' must NOT list Edit (test-writer is write-only, no edits)"
  exit 1
fi

# Persona discipline: tests anchored in PRD spec, NOT in impl plan. The exact
# wording is "Tests validate the PRD spec. Tests do NOT mirror the impl plan."
# Accept any of several phrasings to stay resilient to minor wording drift.
grep -qiE "PRD spec|validate.*PRD|NOT mirror|do NOT mirror|not mirror" "$F" \
  || { echo "FAIL: persona must anchor tests in PRD spec (not mirror the impl plan)"; exit 1; }

# Read priority labels — these EXACT bracket labels per design v0.5 §3.
for label in "[primary]" "[secondary]" "[context]"; do
  grep -qF "$label" "$F" || { echo "FAIL: must use exact read-priority label '$label' (design §3)"; exit 1; }
done

# Reads the per-module PRD and the project-global index PRD (both [primary]).
grep -qF "prd/<module>.md" "$F" || { echo "FAIL: must read prd/<module>.md (primary spec source)"; exit 1; }
grep -qF "prd/_index.md" "$F" || { echo "FAIL: must read prd/_index.md (primary scenario source)"; exit 1; }

# Reads phase plan secondary refs — at least one of ## Objective or ## Verification.
grep -qE "tasks/p<n>_impl\.md ## Objective|tasks/p<n>_impl\.md ## Verification" "$F" \
  || { echo "FAIL: must reference tasks/p<n>_impl.md ## Objective or ## Verification (secondary phase-scope ref)"; exit 1; }

# Phase test path pattern: tests/phase_p<n>_*  inside the update folder.
grep -qF "tests/phase_p<n>_" "$F" \
  || { echo "FAIL: must mention phase test path pattern 'tests/phase_p<n>_'"; exit 1; }

# e2e test paths: per-module e2e/<module>/ AND cross-module e2e/_system/.
grep -qF "e2e/<module>/" "$F" || { echo "FAIL: must mention e2e/<module>/ (per-module capability tests)"; exit 1; }
grep -qF "e2e/_system/" "$F" || { echo "FAIL: must mention e2e/_system/ (cross-module ## Demo scenario tests)"; exit 1; }

# Documents the eleven inputs the orchestrator passes (per design v0.5 §3 +
# commands/impl.md step 2).
for input in project_root module update_dir phase_number phase_name module_prd_path \
             index_prd_path task_plan_path e2e_dir lsp_available prior_tests_glob; do
  grep -qF "$input" "$F" || { echo "FAIL: agent must document input '$input'"; exit 1; }
done

# Karpathy guidelines reference (surgical changes, surface assumptions, define
# verifiable success criteria, avoid overcomplication).
grep -qF "karpathy-guidelines" "$F" || { echo "FAIL: must reference andrej-karpathy-skills:karpathy-guidelines"; exit 1; }

# Per-language naming conventions — at least Python phase + e2e and Node/TS phase + e2e.
grep -qF "phase_p<n>_" "$F" || { echo "FAIL: must mention Python-style phase_p<n>_ phase test naming"; exit 1; }
grep -qF "test_<capability>" "$F" || { echo "FAIL: must mention Python-style test_<capability> e2e naming"; exit 1; }
grep -qE "\.phase\.ts" "$F" || { echo "FAIL: must mention Node/TS-style *.phase.ts phase test naming"; exit 1; }
grep -qE "test\.ts|\.test\.ts" "$F" || { echo "FAIL: must mention Node/TS-style *.test.ts e2e naming"; exit 1; }

# Returns ONE summary line mentioning phase tests + e2e + red.
grep -qiF "phase tests" "$F" || { echo "FAIL: return summary must mention 'phase tests'"; exit 1; }
grep -qiF "e2e" "$F" || { echo "FAIL: return summary must mention e2e"; exit 1; }
grep -qiE "red|currently red|failing" "$F" || { echo "FAIL: return summary must mention 'red' (or failing) state"; exit 1; }

echo OK
