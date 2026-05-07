#!/usr/bin/env bash
# Tests the reverse-prd-architect agent definition (agents/reverse-prd-architect.md).
# This agent is spawned by /super-manus:reverse-prd to write the PRD bundle —
# it owns the architect+PM persona, ASCII diagram rules, content-source priorities,
# and (audit) policy. Orchestrator-level concerns are tested by
# tests/test_command_reverse_prd_logic.sh.

set -euo pipefail
cd "$(dirname "$0")/.."
F=agents/reverse-prd-architect.md
[ -f "$F" ] || { echo "FAIL: missing agent definition agents/reverse-prd-architect.md"; exit 1; }

# Frontmatter — name must match the subagent_type the orchestrator spawns
grep -qE "^name: reverse-prd-architect$" "$F" || { echo "FAIL: frontmatter 'name' must equal 'reverse-prd-architect'"; exit 1; }
grep -qE "^description:" "$F" || { echo "FAIL: frontmatter 'description' is required"; exit 1; }
grep -qE "^tools:" "$F" || { echo "FAIL: frontmatter must declare 'tools' (Read/Write/Edit/Glob/Grep/Bash at minimum)"; exit 1; }

# Persona: chief system architect + senior PM
grep -qiE "chief system architect|system architect" "$F" || { echo "FAIL: persona must be a chief system architect"; exit 1; }
grep -qiE "product manager|senior PM" "$F" || { echo "FAIL: persona must also be a senior PM"; exit 1; }

# Documents the six inputs the orchestrator passes
for input in project_root feature_folder module_list infra_deps monorepo_signals lsp_available; do
  grep -qF "$input" "$F" || { echo "FAIL: agent must document input '$input'"; exit 1; }
done

# Deliverables: word ceilings + file paths + summary line
grep -qF "700" "$F" || { echo "FAIL: must mention 700-word ceiling for prd/_index.md"; exit 1; }
grep -qF "2000" "$F" || { echo "FAIL: must mention 2000-word ceiling for prd/<module>.md"; exit 1; }
grep -qF "prd/_index.md" "$F" || { echo "FAIL: must specify prd/_index.md as a deliverable"; exit 1; }
grep -qF "prd/<module>.md" "$F" || { echo "FAIL: must specify prd/<module>.md as a deliverable"; exit 1; }
grep -qiE "wrote.*module files|summary line" "$F" || { echo "FAIL: must specify the summary line returned to the orchestrator"; exit 1; }

# _index.md eight H2 sections (all must be documented in the agent)
for h in "## Problem" "## Audience" "## Success metrics" "## Demo" "## Must" "## Not doing" "## Modules" "## Data flow overview"; do
  grep -qF "$h" "$F" || { echo "FAIL: agent must document _index.md heading '$h'"; exit 1; }
done

# <module>.md nine H2 sections
for h in "## Why this exists" "## Users" "## Success" "## What users get" "## How it connects" "## Quality bar" "## Risks" "## Out of scope" "## Open questions"; do
  grep -qF "$h" "$F" || { echo "FAIL: agent must document <module>.md heading '$h'"; exit 1; }
done

# ASCII diagram requirement for _index.md ## Data flow overview
grep -qiE "ASCII|box-drawing" "$F" || { echo "FAIL: _index.md ## Data flow overview must include an ASCII diagram"; exit 1; }
grep -qE "┌|┐|└|┘|─|│" "$F" || { echo "FAIL: must list box-drawing characters as the ASCII palette"; exit 1; }

# Module–diagram 1:1 invariant
grep -qiE "module.diagram invariant|module box label|exactly equal a module name" "$F" || { echo "FAIL: must declare the module-diagram 1:1 invariant"; exit 1; }
grep -qiE "offline.*batch modules|offline-modules" "$F" || { echo "FAIL: must require an 'Offline / batch modules: ...' line for modules omitted from the diagram"; exit 1; }

# Diagram source must be the compose depends_on graph + env-URL graph
grep -qiE "compose.*graph|depends_on graph|env-URL graph" "$F" || { echo "FAIL: ## Data flow overview must derive from compose depends_on / env-URL graph"; exit 1; }

# Edge list backup must require a `(for: <capability>)` PM-voice purpose annotation.
# Without this, edges show only protocol — debugging and module-split decisions lose semantic context.
grep -qF "(for:" "$F" || { echo "FAIL: ## Data flow overview edge list spec must require '(for: <capability>)' purpose annotation"; exit 1; }

# Source priorities for content filling
grep -qiE "process entry|Dockerfile CMD|launch target invokes" "$F" || { echo "FAIL: ## What users get must take process entry / Dockerfile CMD as priority 1"; exit 1; }
grep -qiE "depends_on|sibling URL|queue topic|subject name" "$F" || { echo "FAIL: ## How it connects must take compose depends_on / sibling URLs / queue topics as priority 1"; exit 1; }

# ## How it connects must specify an Exposes/Consumes semantic preamble (PM-voice capability nouns
# crossing the module boundary), separate from the structural Upstream/Downstream/Edge-list block.
grep -qF "Exposes:" "$F" || { echo "FAIL: ## How it connects spec must declare an Exposes: preamble"; exit 1; }
grep -qF "Consumes:" "$F" || { echo "FAIL: ## How it connects spec must declare a Consumes: preamble"; exit 1; }
grep -qiE "PM.voice capability|capability noun|capability name in PM voice" "$F" || { echo "FAIL: ## How it connects spec must clarify Exposes/Consumes are PM-voice capability nouns (not endpoints)"; exit 1; }

grep -qiE "library package|packages/\*|workspace.*depend" "$F" || { echo "FAIL: ## Quality bar must include internal library-package imports"; exit 1; }

# Drift check protocol — LSP + grep cooperation, with concrete operations + LSP-unavailable fallback
grep -qF "Drift check protocol" "$F" || { echo "FAIL: must reference using-sm's Drift check protocol"; exit 1; }
grep -qF "LSP" "$F" || { echo "FAIL: must call out LSP as a structural-inference primary tool"; exit 1; }
grep -qiE "workspace symbols|find-references|document symbols" "$F" || { echo "FAIL: must mention at least one concrete LSP operation"; exit 1; }
grep -qiE "double-source|cross-check|both LSP and" "$F" || { echo "FAIL: must articulate the double-source / cross-check rule"; exit 1; }
grep -qiE "LSP unavailable|LSP not available|no language server" "$F" || { echo "FAIL: must specify the LSP-unavailable fallback path"; exit 1; }
grep -qiE "≤10|10 LSP|budget" "$F" || { echo "FAIL: must specify a source-reading budget (≤10 LSP / ≤30 grep+Read)"; exit 1; }

# (audit) policy — single-source only, no bulk
grep -qiE "single.source|do NOT bulk-mark|bulk[ -]mark" "$F" || { echo "FAIL: must restrict (audit) to single-source unverified claims"; exit 1; }

# Granularity default — per-service, do not auto-merge
grep -qiE "per-service|per runtime entry|do NOT merge|do NOT auto-merge" "$F" || { echo "FAIL: must default to per-service module granularity (no auto-merge)"; exit 1; }

# Conservatism — do not invent / fabricate
grep -qiE "invent|guess|fabricate|conservative" "$F" || { echo "FAIL: must instruct the agent to NOT invent details not visible in the source"; exit 1; }

echo OK
