#!/usr/bin/env bash
# Tests commands/impl-all.md — power-mode loop sister of /super-manus:impl.
# Runs the same 3-agent pipeline (architect → test-writer → code-writer → verify
# → close) per phase, looping through ALL pending phases without pausing. Same
# drift checks, same hash-based cheat-prevention, same 3-pass end-of-update gate.
# Aborted runs leave on-disk state identical to /super-manus:impl run that-many-times
# (safety property).

set -euo pipefail
cd "$(dirname "$0")/.."
F=commands/impl-all.md
[ -f "$F" ] || { echo "FAIL: missing commands/impl-all.md"; exit 1; }

# Frontmatter — description must mention loop / all phases / power semantics.
grep -qF "description:" "$F" || { echo "FAIL: missing frontmatter description"; exit 1; }
grep -qE "^description:.*(loop|all phases|all pending phases|power)" "$F" \
  || { echo "FAIL: frontmatter description must mention loop / all phases / power"; exit 1; }

# Active update resolution via sm_active_update helper (no .super-manus/active in v0.4/v0.5).
grep -qF "sm_active_update" "$F" \
  || { echo "FAIL: must use sm_active_update helper (v0.4/v0.5: no .super-manus/active)"; exit 1; }

# Operates on per-update task_plan + per-phase tasks/p<n>_impl.md.
grep -qF "task_plan.md" "$F" || { echo "FAIL: must reference task_plan.md"; exit 1; }
grep -qF "tasks/p" "$F" || { echo "FAIL: must reference tasks/p<n>_impl.md path"; exit 1; }

# Project-global v0.4/v0.5 paths (no per-feature wrapper). impl-all.md cross-refs
# impl.md for the full end-of-update gate spec, so prd_drift and roadmap may
# appear as basenames here — that's fine as long as project-global prd/ is
# anchored. The full-path versions are asserted in test_command_impl_logic.sh.
grep -qF "docs/super-manus/prd/" "$F" || { echo "FAIL: must reference docs/super-manus/prd/ (project-global PRD root)"; exit 1; }
grep -qF "prd_drift.md" "$F" || { echo "FAIL: must reference prd_drift.md (drift log, basename or full path)"; exit 1; }
grep -qF "roadmap.md" "$F" || { echo "FAIL: must reference roadmap.md (basename or full path)"; exit 1; }

# Spawns ALL FOUR agents — architect, reviewer (3 invocations), test-writer, code-writer.
for sub in impl-architect impl-reviewer impl-test-writer impl-code-writer; do
  grep -qE "subagent_type=\"super-manus:${sub}\"" "$F" \
    || { echo "FAIL: must spawn ${sub} via subagent_type=\"super-manus:${sub}\" (v0.9.2 — plugin-namespaced; bare name fails CC resolution)"; exit 1; }
done

# Reviewer 3 invocation modes — pre-test / pre-code / pre-close (v0.7)
for mode in pre-test pre-code pre-close; do
  grep -qF "$mode" "$F" \
    || { echo "FAIL: must reference impl-reviewer mode '$mode'"; exit 1; }
done

# Reviewer verdict types — APPROVE / RETURN_TO_<writer> / ESCALATE (loop driver)
grep -qF "APPROVE" "$F" || { echo "FAIL: must mention reviewer APPROVE verdict"; exit 1; }
grep -qE "RETURN_TO_(ARCHITECT|TEST_WRITER|CODE_WRITER)" "$F" \
  || { echo "FAIL: must mention RETURN_TO_<writer> verdicts"; exit 1; }
grep -qE "ESCALATE_TO_USER|ESCALATE\b" "$F" \
  || { echo "FAIL: must mention ESCALATE verdict"; exit 1; }

# Hash / tamper check: must mention 'code-writer modified tests' OR 'SHA-256'.
grep -qE "code-writer modified tests|SHA-256|sha256|sha-256" "$F" \
  || { echo "FAIL: must mention 'code-writer modified tests' or 'SHA-256' (hash/tamper check)"; exit 1; }

# 3-pass end-of-update gate — Pass 1 (refresh drift), Pass 2 (e2e coverage),
# Pass 3 (pending == 0).
grep -qiE "Pass 1\b|\*\*Pass 1\*\*" "$F" || { echo "FAIL: must label Pass 1 of end-of-update gate"; exit 1; }
grep -qiE "Pass 2\b|\*\*Pass 2\*\*" "$F" || { echo "FAIL: must label Pass 2 of end-of-update gate"; exit 1; }
grep -qiE "Pass 3\b|\*\*Pass 3\*\*" "$F" || { echo "FAIL: must label Pass 3 of end-of-update gate"; exit 1; }
grep -qiE "refresh drift|drift from.*commits|refresh.*from.*commits" "$F" \
  || { echo "FAIL: Pass 1 must describe refreshing drift from commits"; exit 1; }
grep -qiE "e2e coverage" "$F" \
  || { echo "FAIL: Pass 2 must describe e2e coverage check"; exit 1; }
grep -qiE "pending == 0|pending = 0|pending.*0" "$F" \
  || { echo "FAIL: Pass 3 must require pending == 0"; exit 1; }

# Loop semantics — explicit loop / no pause language.
grep -qiE "\bloop\b|without pause|without pausing|no pause|no user pause|continues automatically" "$F" \
  || { echo "FAIL: must describe loop semantics (loop / without pause / no user pause)"; exit 1; }

# Explicit safety property — fallback to /super-manus:impl is safe / on-disk identical.
grep -qiE "fallback to /super-manus:impl|fall.*back.*to.*impl|identical to running.*impl|safe to fall" "$F" \
  || { echo "FAIL: must state safety property (falling back to /super-manus:impl is safe / identical to running impl that-many-times)"; exit 1; }

# Drift check protocol invoked.
grep -qF "Drift check protocol" "$F" \
  || { echo "FAIL: must invoke the using-sm Drift check protocol"; exit 1; }

# BLOCKING / iterating / stable / pending == 0 / BLOCKED — same v0.4 invariants.
grep -qiE "BLOCKING" "$F" || { echo "FAIL: must say end-of-update gate is BLOCKING"; exit 1; }
grep -qiE "iterating" "$F" || { echo "FAIL: must mention 'iterating' roadmap status"; exit 1; }
grep -qiE "stable" "$F" || { echo "FAIL: must mention 'stable' roadmap status"; exit 1; }
grep -qiE "BLOCKED|cannot be marked done|cannot.*complete" "$F" \
  || { echo "FAIL: must say update is BLOCKED when pending drift remains"; exit 1; }

# === v0.7.4 additive assertions ===========================================
# Phase-close inside the loop must synthesize a ## Reflections entry (when
# applicable) so the NEXT iteration's architect spawn picks it up.
grep -qF "## Reflections" "$F" \
  || { echo "FAIL: v0.7.4 loop must reference findings.md ## Reflections (phase-close synthesis)"; exit 1; }
grep -qF "Heuristic" "$F" \
  || { echo "FAIL: v0.7.4 loop must mention the Heuristic line (load-bearing)"; exit 1; }

# v0.8.1: per-agent model override section. impl-all spawns the same 4 agents
# repeatedly across phases — override resolution must be documented per spawn.
grep -qiE "## Per-agent model override|Per-agent model override \(v0\.8" "$F" \
  || { echo "FAIL: v0.8.1 must declare a Per-agent model override section"; exit 1; }
grep -qF "sm_agent_model" "$F" \
  || { echo "FAIL: v0.8.1 must invoke sm_agent_model helper for model resolution"; exit 1; }
grep -qF ".super-manus/agents.yml" "$F" \
  || { echo "FAIL: v0.8.1 must reference .super-manus/agents.yml as the config source (or link to /super-manus:impl which documents it)"; exit 1; }

echo OK
