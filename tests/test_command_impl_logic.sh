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
grep -qE 'subagent_type="impl-architect"' "$F" || { echo "FAIL: must spawn the agent via subagent_type=\"impl-architect\""; exit 1; }

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
  grep -qE "subagent_type=\"${sub}\"" "$F" \
    || { echo "FAIL: v0.7 must spawn ${sub} via subagent_type=\"${sub}\""; exit 1; }
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

echo OK
