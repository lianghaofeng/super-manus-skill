#!/usr/bin/env bash
# Tests the orchestrator slash command commands/reverse-prd.md.
# Content-generation rules live in agents/reverse-prd-architect.md (asserted by
# tests/test_agent_reverse_prd_architect.sh) — this file checks orchestration only.

set -euo pipefail
cd "$(dirname "$0")/.."
F=commands/reverse-prd.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }

# Frontmatter
grep -qF "description:" "$F" || { echo "FAIL: missing frontmatter description"; exit 1; }

# v0.4: project-global super-manus enablement check (no .super-manus/active state file)
grep -qF ".super-manus/active" "$F" && { echo "FAIL: reverse-prd.md must NOT reference .super-manus/active in v0.4"; exit 1; } || true
grep -qF "docs/super-manus/prd/" "$F" || { echo "FAIL: must reference docs/super-manus/prd/ as the v0.4 project-global PRD root"; exit 1; }

# Must produce v0.4 PRD-folder layout: prd/_index.md + per-module prd/<module>.md
grep -qF "prd/_index.md" "$F" || { echo "FAIL: must produce prd/_index.md"; exit 1; }
grep -qF "prd/<module>.md" "$F" || { echo "FAIL: must produce per-module prd/<module>.md files"; exit 1; }

# Must update roadmap.md with the inferred modules
grep -qF "roadmap.md" "$F" || { echo "FAIL: must update roadmap.md"; exit 1; }

# Must be one-shot — user audits afterwards (not interactive Q&A)
grep -qiF "audit" "$F" || { echo "FAIL: must instruct the user to audit/refine after generation"; exit 1; }
grep -qiE "one-shot|one shot" "$F" || { echo "FAIL: must call out the one-shot nature of the command"; exit 1; }

# Must scan project sources to infer module breakdown
grep -qiE "scan|infer|discover" "$F" || { echo "FAIL: must mention scanning / inferring from project sources"; exit 1; }

# Must NOT seed any impl/<m>/<u>/ folders — that's /super-manus:sync's job
grep -qF "/super-manus:sync" "$F" || { echo "FAIL: must redirect to /super-manus:sync for module work after audit"; exit 1; }

# Stage 1 — runtime-first module discovery (declarative-only, no LSP)
grep -qiE "runtime-first|what runs" "$F" || { echo "FAIL: discovery must be framed as runtime-first / 'what runs'"; exit 1; }
grep -qiE "docker-compose|compose\.yaml|orchestration" "$F" || { echo "FAIL: must read compose / orchestration manifests for app services"; exit 1; }
grep -qiE "infra dependenc|infra_deps" "$F" || { echo "FAIL: must classify infra deps (postgres/redis/etc) and exclude from modules"; exit 1; }
grep -qF "Makefile" "$F" || { echo "FAIL: must parse Makefile targets for launch/batch entry points"; exit 1; }
grep -qiE "launch|batch|dev-workflow" "$F" || { echo "FAIL: must classify runnable targets (launch / batch / dev-workflow)"; exit 1; }
grep -qiE "apps/|services/" "$F" || { echo "FAIL: must list workspace app dirs (apps/* / services/*) as module candidates"; exit 1; }
grep -qiE "scripts/" "$F" || { echo "FAIL: must cluster scripts/ by verb prefix as batch-module candidates"; exit 1; }
grep -qiE "no upper cap|no upper bound" "$F" || { echo "FAIL: must remove the 2–5 module cap (monorepos can produce 8–15 modules)"; exit 1; }

# v0.7.2: confirmation gate (replaces v0.6/v0.7.0/v0.7.1 hard-abort) when section already has
# committed (audited) content. Whole-project mode inspects _index.md ## Problem; per-module mode
# inspects prd/<module>.md ## Why this exists. Both prompt the user via AskUserQuestion before
# overwriting — silent overwrite of human-authored PRD content remains forbidden.
grep -qiE "AskUserQuestion|confirmation|confirm.*before" "$F" || { echo "FAIL: must use a confirmation prompt (not silent hard-abort) when section is committed"; exit 1; }
grep -qiE "uncommitted" "$F" || { echo "FAIL: must define the uncommitted classification (placeholder / (audit) only)"; exit 1; }
grep -qiE "committed" "$F" || { echo "FAIL: must define the committed classification (real human-authored content)"; exit 1; }
grep -qiE "OVERWRITE|overwrite" "$F" || { echo "FAIL: confirmation prompt must spell out that proceeding overwrites the file(s)"; exit 1; }

# v0.7.2: per-module mode (refresh just one prd/<module>.md when invoked with a module argument)
grep -qiE "per-module mode|per.module mode" "$F" || { echo "FAIL: must document per-module mode triggered by \$ARGUMENTS"; exit 1; }
grep -qiE "whole-project mode|whole.project mode" "$F" || { echo "FAIL: must document whole-project mode (no argument) as the legacy path"; exit 1; }
grep -qF '$ARGUMENTS' "$F" || { echo "FAIL: must reference \$ARGUMENTS to switch between modes"; exit 1; }
grep -qE '\^\[a-z0-9\]\[a-z0-9-\]\*\$' "$F" || { echo "FAIL: must validate <module> arg with the lowercase-kebab-case regex"; exit 1; }
# Per-module mode contract: do NOT touch other module files / _index.md / roadmap.md
grep -qiE "do NOT touch _index|does NOT touch.*_index|not touch.*_index" "$F" || { echo "FAIL: per-module mode must explicitly NOT touch _index.md"; exit 1; }
grep -qiE "does NOT touch.*roadmap|do NOT.*roadmap|not touch.*roadmap" "$F" || { echo "FAIL: per-module mode must explicitly NOT touch roadmap.md"; exit 1; }

# Per-module mode cascade reporter — find other modules that reference the target in their
# ## How it connects block (or _index.md ## Data flow overview) and surface them, do NOT silently regenerate.
grep -qiE "cascade scan|cascade report|cascade.*may.*stale|may now be stale" "$F" || { echo "FAIL: per-module mode must run a cascade scan and report (not silently regenerate) other modules that reference the target"; exit 1; }

# Per-module mode passes scope=single-module + target_module to the architect
grep -qF "scope" "$F" || { echo "FAIL: must pass 'scope' input to reverse-prd-architect"; exit 1; }
grep -qiE "single-module|target_module" "$F" || { echo "FAIL: must pass single-module scope / target_module to the architect when in per-module mode"; exit 1; }

# Stage 2 — content writing delegated to a named subagent (Agent tool)
grep -qiE "Agent tool|Task tool|subagent_type" "$F" || { echo "FAIL: writing must be delegated to a subagent via the Agent tool"; exit 1; }
grep -qF "reverse-prd-architect" "$F" || { echo "FAIL: must reference the reverse-prd-architect agent by name"; exit 1; }
grep -qF "agents/reverse-prd-architect.md" "$F" || { echo "FAIL: must link to the agent definition file (agents/reverse-prd-architect.md)"; exit 1; }

# Spawning prompt must enumerate the eight inputs the agent expects (v0.7.2: added scope + target_module)
for input in project_root feature_folder scope target_module module_list infra_deps monorepo_signals lsp_available; do
  grep -qF "$input" "$F" || { echo "FAIL: spawning prompt must include input '$input'"; exit 1; }
done

# Orchestrator post-conditions after subagent returns
grep -qiE "1:1 invariant|module.file 1:1|count.*equals the module count" "$F" || { echo "FAIL: orchestrator must verify file count = module count (file-level 1:1 invariant)"; exit 1; }
grep -qiE "Modules.*table|## Modules" "$F" || { echo "FAIL: orchestrator must cross-check ## Modules table rows against actual prd/<name>.md files"; exit 1; }

# v0.8.0: Stage 2 — Runtime probe (passive, runs between Stage 1 module discovery
# and the architect spawn). Gathers what's actually running so the architect can
# distinguish live modules from dead-code residue.
grep -qiE "Stage 2|## Stage 2 — Runtime probe|Runtime probe" "$F" \
  || { echo "FAIL: must document Stage 2 — Runtime probe between Stage 1 and architect spawn"; exit 1; }
grep -qF "scripts/probe-runtime.sh" "$F" \
  || { echo "FAIL: Stage 2 must invoke scripts/probe-runtime.sh (the v0.8.0 passive probe)"; exit 1; }
grep -qF "runtime_facts" "$F" \
  || { echo "FAIL: must capture probe output as runtime_facts and pass it to the architect"; exit 1; }

# v0.8.0: docker compose up gating MUST go through AskUserQuestion — never silent.
# The probe itself stays read-only; only the orchestrator can issue a mutating
# `docker compose up -d`, and only with explicit user consent.
grep -qiE "AskUserQuestion" "$F" \
  || { echo "FAIL: docker startup gating must use AskUserQuestion (cannot silently invoke docker compose up)"; exit 1; }
grep -qiE "(compose.*up.*-d|docker compose -f.*up|Start services)" "$F" \
  || { echo "FAIL: must spell out the 'docker compose up -d' option offered to the user"; exit 1; }
grep -qiE "(60s|60-second|60 seconds|60 ?s wait|up to 60)" "$F" \
  || { echo "FAIL: docker startup must declare a 60-second timeout cap when waiting for services"; exit 1; }

# v0.8.0: agent gets a 9th input named 'runtime_facts'
for input in project_root feature_folder scope target_module module_list infra_deps monorepo_signals lsp_available runtime_facts; do
  grep -qF "$input" "$F" || { echo "FAIL: spawning prompt must include input '$input'"; exit 1; }
done

# v0.8.1: per-agent model override section.
grep -qiE "## Per-agent model override|Per-agent model override \(v0\.8" "$F" \
  || { echo "FAIL: v0.8.1 must declare a Per-agent model override section"; exit 1; }
grep -qF "sm_agent_model" "$F" \
  || { echo "FAIL: v0.8.1 must invoke sm_agent_model helper for model resolution"; exit 1; }

echo OK
