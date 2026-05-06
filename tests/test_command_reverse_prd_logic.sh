#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=commands/reverse-prd.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }

# Frontmatter
grep -qF "description:" "$F" || { echo "FAIL: missing frontmatter description"; exit 1; }

# Must operate within an active super-manus feature
grep -qF ".super-manus/active" "$F" || { echo "FAIL: must read .super-manus/active"; exit 1; }

# Must produce v0.2 PRD-folder layout: prd/_index.md + per-module prd/<module>.md
grep -qF "prd/_index.md" "$F" || { echo "FAIL: must produce prd/_index.md"; exit 1; }
grep -qF "prd/<module>.md" "$F" || { echo "FAIL: must produce per-module prd/<module>.md files"; exit 1; }

# Must update roadmap.md with the inferred modules
grep -qF "roadmap.md" "$F" || { echo "FAIL: must update roadmap.md"; exit 1; }

# Must be one-shot — user audits afterwards (not interactive Q&A)
grep -qiF "audit" "$F" || { echo "FAIL: must instruct the user to audit/refine after generation"; exit 1; }
grep -qiE "one-shot|one shot" "$F" || { echo "FAIL: must call out the one-shot nature of the command"; exit 1; }

# Must scan project sources to infer module breakdown
grep -qiE "scan|infer|analyze" "$F" || { echo "FAIL: must mention scanning / inferring from project sources"; exit 1; }

# Must NOT seed any impl/<m>/<u>/ folders — that's /super-manus:sync's job
grep -qF "/super-manus:sync" "$F" || { echo "FAIL: must redirect to /super-manus:sync for module work after audit"; exit 1; }

# Must respect 700 / 2000 word ceilings just like /brainstorm
grep -qF "700" "$F" || { echo "FAIL: must mention 700-word ceiling for prd/_index.md"; exit 1; }
grep -qF "2000" "$F" || { echo "FAIL: must mention 2000-word ceiling for prd/<module>.md"; exit 1; }

# Must not invent product details that aren't in the source — instructions to be conservative
grep -qiE "invent|guess|fabricate|conservative" "$F" || { echo "FAIL: must instruct the agent to NOT invent details not visible in the source"; exit 1; }

# Must use the Drift check protocol from using-sm (LSP + grep cooperation, not pure grep) for content filling
grep -qF "Drift check protocol" "$F" || { echo "FAIL: must reference using-sm's Drift check protocol"; exit 1; }
grep -qF "LSP" "$F" || { echo "FAIL: must call out LSP as a structural-inference primary tool"; exit 1; }
grep -qiE "workspace symbols|find-references|document symbols" "$F" || { echo "FAIL: must mention at least one concrete LSP operation"; exit 1; }
grep -qiE "double-source|cross-check|both LSP and" "$F" || { echo "FAIL: must articulate the double-source / cross-check rule"; exit 1; }
grep -qiE "LSP unavailable|LSP not available|no language server" "$F" || { echo "FAIL: must specify the LSP-unavailable fallback path"; exit 1; }

# Module discovery is runtime-first (declarative), not LSP-led
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

# Content-filling source priorities (Step 2): declarative-first, LSP last
grep -qiE "process entry|Dockerfile CMD|launch target invokes" "$F" || { echo "FAIL: ## Surface must take process entry / Dockerfile CMD as priority 1"; exit 1; }
grep -qiE "depends_on|sibling URL|queue topic|subject name" "$F" || { echo "FAIL: ## Data flow must take compose depends_on / sibling URLs / queue topics as priority 1"; exit 1; }
grep -qiE "infra_deps|infra dependenc" "$F" || { echo "FAIL: ## Constraints must enumerate infra_deps from Stage 1.1"; exit 1; }
grep -qiE "library package|packages/\*|workspace.*depend" "$F" || { echo "FAIL: ## Constraints must include internal library-package imports"; exit 1; }

# (audit) policy — single-source only, no bulk marking
grep -qiE "single.source|do NOT bulk-mark|bulk[ -]mark" "$F" || { echo "FAIL: must restrict (audit) to single-source unverified claims, not bulk filler"; exit 1; }

# Granularity default — per-service / per runtime entry, do not auto-merge
grep -qiE "per-service|per runtime entry|do NOT merge" "$F" || { echo "FAIL: must default to per-service module granularity (no auto-merge)"; exit 1; }

# _index.md ## Data flow overview from compose graph, not textual inference
grep -qiE "compose.*graph|depends_on graph|env-URL graph" "$F" || { echo "FAIL: _index.md ## Data flow overview must derive from compose depends_on / env-URL graph"; exit 1; }

echo OK
