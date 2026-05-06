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

# Hard-abort gate when active feature already has a committed PRD topic
grep -qiE "hard-abort|hard abort" "$F" || { echo "FAIL: must hard-abort when active feature is topic-scoped (no overwrite prompt)"; exit 1; }
grep -qiE "topic-scoped|committed PRD topic|committed.*topic" "$F" || { echo "FAIL: must describe the topic-scoped/committed-PRD condition that triggers abort"; exit 1; }

# Stage 2 — content writing delegated to a named subagent (Agent tool)
grep -qiE "Agent tool|Task tool|subagent_type" "$F" || { echo "FAIL: writing must be delegated to a subagent via the Agent tool"; exit 1; }
grep -qF "reverse-prd-architect" "$F" || { echo "FAIL: must reference the reverse-prd-architect agent by name"; exit 1; }
grep -qF "agents/reverse-prd-architect.md" "$F" || { echo "FAIL: must link to the agent definition file (agents/reverse-prd-architect.md)"; exit 1; }

# Spawning prompt must enumerate the six inputs the agent expects
for input in project_root feature_folder module_list infra_deps monorepo_signals lsp_available; do
  grep -qF "$input" "$F" || { echo "FAIL: spawning prompt must include input '$input'"; exit 1; }
done

# Orchestrator post-conditions after subagent returns
grep -qiE "1:1 invariant|module.file 1:1|count.*equals the module count" "$F" || { echo "FAIL: orchestrator must verify file count = module count (file-level 1:1 invariant)"; exit 1; }
grep -qiE "Modules.*table|## Modules" "$F" || { echo "FAIL: orchestrator must cross-check ## Modules table rows against actual prd/<name>.md files"; exit 1; }

echo OK
