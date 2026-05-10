#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
F=commands/impl.md
[ -f "$F" ] || { echo "FAIL: missing"; exit 1; }

# Frontmatter
grep -qF "description:" "$F" || { echo "FAIL: missing frontmatter description"; exit 1; }

# v0.4: there is no .super-manus/active state file. Active update is resolved by mtime scan via sm_active_update.
grep -qF "sm_active_update" "$F" || { echo "FAIL: must use sm_active_update helper to resolve active update (v0.4)"; exit 1; }

# Operates on v0.4 layout (per-update task_plan.md, tasks/p<n>_impl.md inside the update folder)
grep -qF "task_plan.md" "$F" || { echo "FAIL: must reference task_plan.md (per-update)"; exit 1; }
grep -qF "tasks/p" "$F" || { echo "FAIL: must reference tasks/p<n>_impl.md path"; exit 1; }

# v0.4 path invariants — project-global, no <feature>/ prefix
grep -qF "docs/super-manus/prd/" "$F" || { echo "FAIL: must use v0.4 project-global prd path docs/super-manus/prd/"; exit 1; }
grep -qF "docs/super-manus/prd_drift.md" "$F" || { echo "FAIL: must reference docs/super-manus/prd_drift.md (project-global drift log)"; exit 1; }
grep -qF "docs/super-manus/roadmap.md" "$F" || { echo "FAIL: must reference docs/super-manus/roadmap.md (project-global roadmap)"; exit 1; }

# Drift detection: must read prd/<module>.md and append a prd_drift.md row on conflict
grep -qF "prd/<module>.md" "$F" || { echo "FAIL: must read per-module PRD"; exit 1; }
grep -qF "prd_drift.md" "$F" || { echo "FAIL: must reference prd_drift.md for drift logging"; exit 1; }
grep -qiF "drift" "$F" || { echo "FAIL: must call out drift detection responsibility"; exit 1; }

# Must NOT silently update PRD — drift always logged, user-decided
grep -qiF "/super-manus:prd-update" "$F" || { echo "FAIL: must point user at prd-update for resolution"; exit 1; }

# Must auto-find next pending phase
grep -qiF "pending" "$F" || { echo "FAIL: must mention pending phase auto-selection"; exit 1; }

# Must seed the per-phase plan via the impl-architect subagent (no inline persona)
grep -qF "phase_plan.md" "$F" || { echo "FAIL: must use phase_plan.md template to seed missing impl plan"; exit 1; }
grep -qF "agents/impl-architect.md" "$F" || { echo "FAIL: must link to agents/impl-architect.md"; exit 1; }
grep -qF "impl-architect" "$F" || { echo "FAIL: must reference the impl-architect agent by name"; exit 1; }
grep -qE 'subagent_type="super-manus:impl-architect"' "$F" || { echo "FAIL: must spawn the agent via subagent_type=\"super-manus:impl-architect\" (v0.9.2 — plugin-namespaced; bare name fails CC plugin agent resolution)"; exit 1; }

# Spawning prompt must enumerate the ten inputs the impl-architect agent expects
for input in project_root module update_dir phase_number phase_name module_prd_path task_plan_path findings_path progress_path lsp_available; do
  grep -qF "$input" "$F" || { echo "FAIL: spawning prompt must include input '$input'"; exit 1; }
done

# Argument flexibility: target may be omitted, an update name, or a module name
grep -qiF "target" "$F" || { echo "FAIL: must document optional target argument"; exit 1; }

# Must NOT touch progress.md by hand (hook-managed)
grep -qiF "progress.md" "$F" || { echo "FAIL: must mention progress.md (specifically: not to hand-edit)"; exit 1; }

# Drift check uses the using-sm Drift check protocol (LSP + grep cooperation)
grep -qF "Drift check protocol" "$F" || { echo "FAIL: impl.md must reference using-sm's Drift check protocol"; exit 1; }
grep -qF "LSP" "$F" || { echo "FAIL: impl.md drift check must invoke LSP, not just text scan"; exit 1; }
grep -qiE "double-source|cross-check|both LSP and" "$F" || { echo "FAIL: impl.md must keep the double-source rule visible"; exit 1; }

# End-of-update drift gate is BLOCKING (cannot soft-pass with pending drift)
grep -qiE "End-of-update drift gate|drift gate.*BLOCKING|BLOCKING.*drift gate" "$F" || { echo "FAIL: impl.md must define a BLOCKING end-of-update drift gate, not a soft consistency check"; exit 1; }
grep -qiE "pending.*0|pending == 0|pending = 0|pending row.*zero|zero.*pending" "$F" || { echo "FAIL: gate must require zero pending prd_drift rows for the module before completion"; exit 1; }
grep -qiE "BLOCKED|cannot be marked done|cannot.*complete" "$F" || { echo "FAIL: gate must explicitly block update completion when pending drift remains"; exit 1; }
grep -qiF "iterating" "$F" || { echo "FAIL: must mention the 'iterating' roadmap status the gate refuses to advance from"; exit 1; }
grep -qiF "stable" "$F" || { echo "FAIL: must mention 'stable' as the roadmap status only reachable after the gate passes"; exit 1; }

# Two resolution paths must be documented (prd-update OR revert + findings note)
grep -qiE "reverted|revert.*implementation" "$F" || { echo "FAIL: gate must document the 'revert implementation' resolution path (with Resolution=reverted)"; exit 1; }
grep -qiF "findings.md" "$F" || { echo "FAIL: revert path must require a findings.md ## Decisions entry"; exit 1; }

# === v0.5 additive assertions ============================================
# v0.5 splits the v0.4 single impl-executor into a 3-agent pipeline (architect →
# test-writer → code-writer). The orchestrator hashes test files between
# test-writer and code-writer; tamper aborts the phase. End-of-update gate gains
# a Pass 2 (e2e coverage). Per-phase terminal: more pending → STOP; no pending →
# end-of-update gate. /super-manus:impl-all is the loop alternative.

# Spawns ALL FOUR agents — architect / reviewer / test-writer / code-writer (v0.7).
for sub in impl-architect impl-reviewer impl-test-writer impl-code-writer; do
  grep -qE "subagent_type=\"super-manus:${sub}\"" "$F" \
    || { echo "FAIL: v0.9.2 must spawn ${sub} via subagent_type=\"super-manus:${sub}\" (plugin-namespaced; bare name fails CC resolution)"; exit 1; }
done

# === v0.7 additive assertions =============================================
# v0.7 inserts impl-reviewer at 3 checkpoints (pre-test / pre-code / pre-close)
# with per-checkpoint counters (max 2 RETURNs per checkpoint, 3rd → ESCALATE).
# Reviewer is read-only by tool surface; cheat-prevention semantics preserved.
# Hash baseline is established AFTER review #2 APPROVE (not before).

# Three reviewer modes
for mode in pre-test pre-code pre-close; do
  grep -qF "$mode" "$F" || { echo "FAIL: v0.7 must document reviewer mode '$mode'"; exit 1; }
done

# Reviewer verdicts — APPROVE / RETURN_TO_<writer> / ESCALATE_TO_USER
grep -qF "APPROVE" "$F" || { echo "FAIL: v0.7 must document reviewer APPROVE verdict"; exit 1; }
grep -qE "RETURN_TO_(ARCHITECT|TEST_WRITER|CODE_WRITER)" "$F" \
  || { echo "FAIL: v0.7 must document RETURN_TO_<writer> verdicts"; exit 1; }
grep -qE "ESCALATE_TO_USER|ESCALATE\b" "$F" \
  || { echo "FAIL: v0.7 must document ESCALATE verdict"; exit 1; }

# Per-checkpoint retry counter (3 attempts max, 3rd → ESCALATE)
grep -qiE "counter\[#1\]|counter\[#2\]|counter\[#3\]|per[- ]checkpoint counter" "$F" \
  || { echo "FAIL: v0.7 must implement per-checkpoint retry counter"; exit 1; }
grep -qiE "> 2|max 2|≤2|<= 2" "$F" \
  || { echo "FAIL: v0.7 must enforce retry budget (max 2 RETURNs per checkpoint)"; exit 1; }

# previous_attempt_feedback passed on re-spawn
grep -qF "previous_attempt_feedback" "$F" \
  || { echo "FAIL: v0.7 must pass previous_attempt_feedback on writer re-spawn"; exit 1; }

# Hash check between test-writer and code-writer.
grep -qE "code-writer modified tests|SHA-256|sha256|sha-256|hash" "$F" \
  || { echo "FAIL: v0.5 must mention hash check (SHA-256 / 'code-writer modified tests' / hash)"; exit 1; }

# Phase tests path pattern (v0.5 NEW: tests/ subfolder inside the update folder).
grep -qE "phase_p<n>_|tests/phase" "$F" \
  || { echo "FAIL: v0.5 must reference phase tests path (phase_p<n>_ or tests/phase)"; exit 1; }

# e2e coverage Pass — Pass 2 of the 3-pass end-of-update gate.
grep -qiE "e2e coverage|Pass 2|e2e/<module>/" "$F" \
  || { echo "FAIL: v0.5 must mention e2e coverage Pass (Pass 2) of the end-of-update gate"; exit 1; }

# One-phase terminal behavior: more pending → STOP; no pending → end-of-update gate.
grep -qiE "more pending|pending phases remain|next pending phase" "$F" \
  || { echo "FAIL: v0.5 must describe 'more pending phases remain' terminal branch"; exit 1; }
grep -qiE "no pending|no more pending|fall through to.*end-of-update|fall through.*drift gate" "$F" \
  || { echo "FAIL: v0.5 must describe 'no pending → end-of-update gate' terminal branch"; exit 1; }

# Cross-link to the loop alternative /super-manus:impl-all.
grep -qF "/super-manus:impl-all" "$F" \
  || { echo "FAIL: v0.5 must cross-link the loop alternative /super-manus:impl-all"; exit 1; }

# === v0.7.4 additive assertions ===========================================
# v0.7.4 adds Reflexion-style cross-phase memory: orchestrator synthesizes a
# Reflection entry at phase close (when the phase had >=1 reviewer RETURN) and
# the next phase's impl-architect spawn includes ## Reflections as
# `prior_reflections`.

# Architect spawning prompt must include `prior_reflections` input.
grep -qF "prior_reflections" "$F" \
  || { echo "FAIL: v0.7.4 must pass prior_reflections to impl-architect (spawning prompt input)"; exit 1; }

# Phase-close step must mention synthesis of ## Reflections (or the section name itself).
grep -qF "## Reflections" "$F" \
  || { echo "FAIL: v0.7.4 must reference findings.md ## Reflections (phase-close synthesis target)"; exit 1; }

# The synthesis must reference the 3-bullet shape (Misstep / Root cause / Heuristic).
grep -qF "Heuristic" "$F" \
  || { echo "FAIL: v0.7.4 phase-close synthesis must produce a Heuristic bullet (the load-bearing line)"; exit 1; }
grep -qF "Misstep" "$F" \
  || { echo "FAIL: v0.7.4 phase-close synthesis must produce a Misstep bullet"; exit 1; }
grep -qF "Root cause" "$F" \
  || { echo "FAIL: v0.7.4 phase-close synthesis must produce a Root cause bullet"; exit 1; }

# Synthesis must skip when the phase had zero RETURN events.
grep -qiE "Zero RETURN|zero reviewer RETURN|skip.*entry|skipped when.*zero" "$F" \
  || { echo "FAIL: v0.7.4 must skip Reflection entry when the phase had zero reviewer RETURN events"; exit 1; }

# v0.8.1: per-agent model override section. Spawning commands must document
# the sm_agent_model lookup so the orchestrator can pass `model:` to the
# Agent tool when the user has set an override in .super-manus/agents.yml.
grep -qiE "## Per-agent model override|Per-agent model override \(v0\.8" "$F" \
  || { echo "FAIL: v0.8.1 must declare a Per-agent model override section"; exit 1; }
grep -qF "sm_agent_model" "$F" \
  || { echo "FAIL: v0.8.1 must invoke sm_agent_model helper for model resolution"; exit 1; }
grep -qF ".super-manus/agents.yml" "$F" \
  || { echo "FAIL: v0.8.1 override must reference .super-manus/agents.yml as the config source"; exit 1; }
grep -qF "CLAUDE_CODE_EFFORT_LEVEL" "$F" \
  || { echo "FAIL: v0.8.2 must document the CLAUDE_CODE_EFFORT_LEVEL env var as the effort override path (effort is overridable, just not via .super-manus/agents.yml)"; exit 1; }
grep -qiE "effort.*highest|highest.*effort|env var.*highest|highest.*priority" "$F" \
  || { echo "FAIL: v0.8.2 must clarify env var has highest priority (overrides frontmatter)"; exit 1; }

# === v0.9.4 R4: code-writer commit hygiene + whitelist mechanical check ====
# Orchestrator must (a) snapshot the working tree before spawning code-writer,
# parse `## Files touched` into a whitelist, and prompt the user when dirty
# files overlap with phase scope; (b) after the code-writer returns, mechanical-
# match every committed/staged path against the whitelist and prompt on
# violation. Both prompts go through AskUserQuestion — no silent auto-reset.

grep -qF "sm_parse_files_touched" "$F" \
  || { echo "FAIL: v0.9.4 R4 must reference sm_parse_files_touched helper for whitelist parsing"; exit 1; }
grep -qF "sm_whitelist_match" "$F" \
  || { echo "FAIL: v0.9.4 R4 must reference sm_whitelist_match helper for whitelist matching"; exit 1; }
grep -qiE "pre-spawn working[- ]tree check|working[- ]tree check" "$F" \
  || { echo "FAIL: v0.9.4 R4 must define a pre-spawn working-tree check before code-writer spawn"; exit 1; }
grep -qiE "post-return.*whitelist|commit whitelist check|whitelist check.*code-writer|code-writer.*whitelist" "$F" \
  || { echo "FAIL: v0.9.4 R4 must define a post-return commit whitelist check on code-writer commits"; exit 1; }
grep -qF "AskUserQuestion" "$F" \
  || { echo "FAIL: v0.9.4 R4 must surface violations via AskUserQuestion (no silent auto-reset)"; exit 1; }
grep -qF "OUT_OF_SCOPE_DIRTY" "$F" \
  || { echo "FAIL: v0.9.4 R4 must handle the OUT_OF_SCOPE_DIRTY early-return from code-writer"; exit 1; }
grep -qF "PRE_CODEWRITER_HEAD" "$F" \
  || { echo "FAIL: v0.9.4 R4 must snapshot pre-code-writer HEAD for precise reset on violation"; exit 1; }

# === v0.9.4 R5: two-pass architect spawn + existing_code_facts injection ===
# Orchestrator must split Step 1 into 1a (Pass 1 spawn) → 1b (compute facts)
# → 1c (Pass 2 spawn). On RETURN_TO_ARCHITECT from any reviewer checkpoint,
# re-spawn ONLY Pass 2 with previous_attempt_feedback AND previous_architect_draft.

grep -qiE "Step 1a|Pass 1 spawn|two-pass" "$F" \
  || { echo "FAIL: v0.9.4 R5 must split Step 1 into Pass 1 (1a)"; exit 1; }
grep -qiE "Step 1b|Compute existing|compute.*facts" "$F" \
  || { echo "FAIL: v0.9.4 R5 must have Step 1b for compute existing_code_facts between passes"; exit 1; }
grep -qiE "Step 1c|Pass 2 spawn" "$F" \
  || { echo "FAIL: v0.9.4 R5 must have Step 1c for Pass 2 spawn"; exit 1; }

# pass input flag (1 vs 2)
grep -qE "pass: 1|pass.{0,3}=.{0,3}1" "$F" \
  || { echo "FAIL: v0.9.4 R5 must document pass=1 input flag"; exit 1; }
grep -qE "pass: 2|pass.{0,3}=.{0,3}2" "$F" \
  || { echo "FAIL: v0.9.4 R5 must document pass=2 input flag"; exit 1; }

# Helper for computing fact block
grep -qF "sm_compute_existing_code_facts" "$F" \
  || { echo "FAIL: v0.9.4 R5 must invoke sm_compute_existing_code_facts helper"; exit 1; }

# Pass 1 YAML artifact path
grep -qF ".pass1_files_touched_p" "$F" \
  || { echo "FAIL: v0.9.4 R5 must reference .pass1_files_touched_p<n>.yml artifact"; exit 1; }

# Pass 2 spawn carries pass1_files_touched + existing_code_facts
grep -qF "pass1_files_touched" "$F" \
  || { echo "FAIL: v0.9.4 R5 Pass 2 spawn must carry pass1_files_touched input"; exit 1; }
grep -qF "existing_code_facts" "$F" \
  || { echo "FAIL: v0.9.4 R5 Pass 2 spawn must carry existing_code_facts input"; exit 1; }

# RETURN_TO_ARCHITECT re-spawn injects previous_architect_draft
grep -qF "previous_architect_draft" "$F" \
  || { echo "FAIL: v0.9.4 R5 RETURN_TO_ARCHITECT must inject previous_architect_draft fact block"; exit 1; }

# Re-spawn only Pass 2 — Pass 1 invariant within a phase
grep -qiE "Pass 2 ONLY|ONLY Pass 2|Pass 2 \\(Step 1c\\)|Pass 1 is invariant|Pass 1.*invariant" "$F" \
  || { echo "FAIL: v0.9.4 R5 RETURN re-spawn must target Pass 2 only (Pass 1 invariant within phase)"; exit 1; }

# Phase close cleans up Pass 1 YAML alongside test hash file
grep -qF ".pass1_files_touched_p<n>.yml" "$F" \
  || { echo "FAIL: v0.9.4 R5 phase close must delete .pass1_files_touched_p<n>.yml temp artifact"; exit 1; }

echo OK
