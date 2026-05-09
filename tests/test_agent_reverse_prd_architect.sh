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

# v0.8.0: reverse-prd-architect synthesizes a whole-project PRD bundle in one
# pass — the heaviest single-shot agent in the plugin. Pinned to opus + max.
grep -qE "^model: opus$" "$F" || { echo "FAIL: frontmatter must pin 'model: opus' (system-level synthesis)"; exit 1; }
grep -qE "^effort: max$" "$F" || { echo "FAIL: frontmatter must declare 'effort: max' (whole-project PRD synthesis)"; exit 1; }

# Persona: chief system architect + senior PM
grep -qiE "chief system architect|system architect" "$F" || { echo "FAIL: persona must be a chief system architect"; exit 1; }
grep -qiE "product manager|senior PM" "$F" || { echo "FAIL: persona must also be a senior PM"; exit 1; }

# Documents the eight inputs the orchestrator passes (v0.7.2: scope + target_module added)
for input in project_root feature_folder scope target_module module_list infra_deps monorepo_signals lsp_available; do
  grep -qF "$input" "$F" || { echo "FAIL: agent must document input '$input'"; exit 1; }
done

# v0.7.2: scope=single-module deliverable contract — write only prd/<target_module>.md, do NOT
# touch _index.md or any other prd/<other>.md. Cascade discovery is the orchestrator's job, not
# the architect's; agent must NOT silently regenerate other modules even if it sees them affected.
grep -qiE "single-module" "$F" || { echo "FAIL: agent must document scope=single-module behavior"; exit 1; }
grep -qiE "whole-project" "$F" || { echo "FAIL: agent must document scope=whole-project behavior"; exit 1; }
grep -qiE "do NOT write [^a-zA-Z]*_index|not write [^a-zA-Z]*_index|do NOT touch [^a-zA-Z]*_index" "$F" || { echo "FAIL: per-module scope must explicitly forbid writing _index.md"; exit 1; }
grep -qiE "do NOT write any other|not write any other|forbid.*other module" "$F" || { echo "FAIL: per-module scope must explicitly forbid writing other prd/<other>.md files"; exit 1; }

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

# v0.8.3: Mermaid is the canonical format for the architecture diagram
# (replaces the v0.7.x box-drawing ASCII spec). Render natively in GitHub PR
# review and IDE preview, structured DSL agents can both write and parse.
grep -qF "Mermaid" "$F" || { echo "FAIL: _index.md ## Data flow overview must require a Mermaid diagram (v0.8.3)"; exit 1; }
grep -qE "flowchart\s+(TD|LR)" "$F" || { echo "FAIL: must specify Mermaid flowchart direction (TD or LR)"; exit 1; }
# Three node-shape conventions: module rectangle / infra cylinder / external stadium —
# spec must enumerate at least the module + infra distinction (the load-bearing one).
grep -qE "MODULE node" "$F" || { echo "FAIL: must declare the MODULE node shape rule"; exit 1; }
grep -qE "INFRA-DEP node" "$F" || { echo "FAIL: must declare the INFRA-DEP node shape rule"; exit 1; }
# Spec must include at least one Mermaid syntax example to anchor the architect's output.
grep -qE '```mermaid' "$F" || { echo "FAIL: spec must include a fenced \`\`\`mermaid example block"; exit 1; }
# Box-drawing palette must be GONE (was the v0.7.x spec, superseded by Mermaid).
if grep -qE "┌|┐|└|┘" "$F"; then
  echo "FAIL: v0.8.3 spec must not retain the v0.7.x ASCII box-drawing palette — Mermaid replaces it"
  exit 1
fi

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

# v0.8.0: runtime_facts input — the architect cross-validates static reading
# against passive runtime evidence collected by the orchestrator's Stage 2 probe.
grep -qF "runtime_facts" "$F" || { echo "FAIL: agent must document the v0.8.0 runtime_facts input"; exit 1; }

# v0.8.0: explicit Cross-validation protocol section
grep -qF "## Cross-validation with runtime_facts" "$F" \
  || { echo "FAIL: agent must declare a '## Cross-validation with runtime_facts' section"; exit 1; }

# v0.8.0: three (audit) subtypes for runtime/static disagreement
grep -qF "runtime-unverified" "$F" || { echo "FAIL: must declare (audit — runtime-unverified) subtype for static-only claims when probe ran"; exit 1; }
grep -qF "runtime-only"   "$F" || { echo "FAIL: must declare (audit — runtime-only) subtype for runtime-only claims (e.g. OpenAPI route with no static source)"; exit 1; }
grep -qF "source-runtime-conflict"   "$F" || { echo "FAIL: must declare (audit — source-runtime-conflict) subtype for static/runtime disagreement"; exit 1; }

# v0.8.0: tool budget formula 10 + 5×N + 10 with hard cap 60 (replaces v0.7.x flat ≤10/≤30 cap)
grep -qF "## Tool budget" "$F" || { echo "FAIL: must declare a '## Tool budget' section"; exit 1; }
grep -qE "10 \+ 5" "$F" || { echo "FAIL: must declare the budget formula '10 + 5 × N + 10'"; exit 1; }
grep -qE "(\b60\b|cap.*60|60.*cap)" "$F" || { echo "FAIL: must declare hard cap of 60 calls"; exit 1; }

# v0.8.0: runtime_facts must be flagged as 'free' / highest-density tool to read first
grep -qiE "runtime_facts.*free|free.*runtime_facts|already in your input" "$F" \
  || { echo "FAIL: tool budget must rank runtime_facts as a free (already-in-input) high-density source"; exit 1; }

echo OK
