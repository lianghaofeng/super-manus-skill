#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_ROOT="$(pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

sm_start() {
  SUPER_MANUS_ROOT="$REPO_ROOT" bash "$REPO_ROOT/scripts/sm-start.sh" "$@"
}
sm_update() {
  SUPER_MANUS_ROOT="$REPO_ROOT" bash "$REPO_ROOT/scripts/sm-update.sh" "$@"
}

# Case A: /sync command markdown exists and has v0.4 contract markers
F="$REPO_ROOT/commands/sync.md"
[ -f "$F" ] || { echo "FAIL: commands/sync.md missing"; exit 1; }

# v0.4: project-global PRD root (no per-feature wrapper). Mentions of .super-manus/active are
# allowed ONLY when paired with "no" / "not" / "removed" wording (i.e. documenting the v0.3→v0.4 migration);
# never as an active read instruction.
grep -qF "docs/super-manus/prd/" "$F" || { echo "FAIL: sync.md must reference docs/super-manus/prd/ as the v0.4 project-global PRD root"; exit 1; }
bad_active=$(grep -nF ".super-manus/active" "$F" | grep -viE "no .super-manus/active|not .super-manus/active|removed|gone|v0\.4" || true)
if [ -n "$bad_active" ]; then
  echo "FAIL: sync.md must NOT reference .super-manus/active as an active read in v0.4 (found):"
  echo "$bad_active"
  exit 1
fi

# Must read git diff of docs/super-manus/prd/<module>.md to infer milestone intent
grep -qF "git diff" "$F" || { echo "FAIL: sync.md must read git diff to infer milestone intent"; exit 1; }
grep -qF "docs/super-manus/prd/<module>.md" "$F" || { echo "FAIL: sync.md must diff docs/super-manus/prd/<module>.md"; exit 1; }

# Must invoke sm-update.sh to scaffold the update folder
grep -qF "scripts/sm-update.sh" "$F" || { echo "FAIL: sync.md must invoke scripts/sm-update.sh"; exit 1; }
grep -qF "prd/<module>.md" "$F" || { echo "FAIL: sync.md must reference per-module PRD"; exit 1; }

# Must reference the sync-planner subagent by name and spawn it via Agent tool with subagent_type
grep -qF "sync-planner" "$F" || { echo "FAIL: sync.md must reference the sync-planner agent by name"; exit 1; }
grep -qE 'subagent_type="super-manus:sync-planner"' "$F" || { echo "FAIL: sync.md must spawn the agent via subagent_type=\"super-manus:sync-planner\" (v0.9.2 — plugin-namespaced; bare name fails CC resolution)"; exit 1; }

# Spawning prompt must enumerate the six inputs the agent expects
for input in project_root module update_name module_prd_path prd_diff lsp_available; do
  grep -qF "$input" "$F" || { echo "FAIL: spawning prompt must include input '$input'"; exit 1; }
done

# Must inject the planner-drafted Phases into the scaffolded task_plan.md
grep -qF "task_plan.md" "$F" || { echo "FAIL: sync.md must reference task_plan.md (Phases injection target)"; exit 1; }
grep -qiE "inject|replace|Phases" "$F" || { echo "FAIL: sync.md must describe injecting the planner's Phases table into task_plan.md"; exit 1; }

# v0.4: must NOT auto-run /super-manus:impl — user must audit phases first
grep -qiE "auto.run|automatically run|do NOT.*impl|forbidden in v0\.4" "$F" || { echo "FAIL: sync.md must NOT auto-run /super-manus:impl (user audits phases first)"; exit 1; }

# Drift between PRD edit and code is usually skipped (the user just wrote the intent),
# but the file must still surface drift terminology so the user knows to use /super-manus:prd-update for deletions.
grep -qiF "drift" "$F" || { echo "FAIL: sync.md must mention drift handling"; exit 1; }

# Case B: invalid args
if sm_update 2>/dev/null; then echo "FAIL: missing args should be rejected"; exit 1; fi
if sm_update "api" 2>/dev/null; then echo "FAIL: single arg should be rejected"; exit 1; fi
if sm_update "API" "mvp" 2>/dev/null; then echo "FAIL: uppercase module should be rejected"; exit 1; fi
if sm_update "api" "MVP" 2>/dev/null; then echo "FAIL: uppercase update name should be rejected"; exit 1; fi
if sm_update "-leading" "mvp" 2>/dev/null; then echo "FAIL: leading hyphen module should be rejected"; exit 1; fi

# Case C: super-manus not enabled (no docs/super-manus/prd/) → exit non-zero
if sm_update "api" "mvp" 2>/dev/null; then echo "FAIL: missing docs/super-manus/prd/ should be rejected"; exit 1; fi

# Case E: happy path — enable super-manus, run sm-update for module 'api' with name 'mvp'
sm_start >/dev/null
TODAY=$(date +%F)
out=$(sm_update "api" "mvp")
UPDATE="docs/super-manus/impl/api/${TODAY}-mvp"
[ -d "$UPDATE" ] || { echo "FAIL: update folder not created at $UPDATE"; exit 1; }
[ -f "$UPDATE/task_plan.md" ] || { echo "FAIL: task_plan.md not seeded"; exit 1; }
[ -f "$UPDATE/findings.md" ] || { echo "FAIL: findings.md not seeded"; exit 1; }
[ -f "$UPDATE/progress.md" ] || { echo "FAIL: progress.md not seeded"; exit 1; }
[ -d "$UPDATE/tasks" ] || { echo "FAIL: tasks/ subfolder not created"; exit 1; }

# task_plan.md must rewrite prd.md → relative path to per-module PRD (impl/<m>/<u>/.. → ../../../prd/<m>.md)
grep -qF "../../../prd/api.md" "$UPDATE/task_plan.md" || { echo "FAIL: task_plan.md should point at ../../../prd/api.md, got:"; cat "$UPDATE/task_plan.md"; exit 1; }

# Roadmap should now have an api row with status=iterating
grep -qE "^\| api \| iterating \|" "docs/super-manus/roadmap.md" || { echo "FAIL: roadmap.md should have api row with iterating status, got:"; cat "docs/super-manus/roadmap.md"; exit 1; }
# Placeholder <module-a> row should be gone
grep -qF "<module-a>" "docs/super-manus/roadmap.md" && { echo "FAIL: roadmap placeholder <module-a> row should have been dropped after first sm-update"; exit 1; } || true

# Echoed path should be the new update folder
echo "$out" | grep -q "$UPDATE" || { echo "FAIL: echo path should match update folder, got: $out"; exit 1; }

# Case F: re-running with same args → exit non-zero (folder exists)
if sm_update "api" "mvp" 2>/dev/null; then echo "FAIL: duplicate update should be rejected"; exit 1; fi

# Case G: second module gets its own row appended; first module's iterating status preserved
sm_update "frontend" "mvp" >/dev/null
grep -qE "^\| api \| iterating \|" "docs/super-manus/roadmap.md" || { echo "FAIL: api row should still be iterating after frontend sm-update"; exit 1; }
grep -qE "^\| frontend \| iterating \|" "docs/super-manus/roadmap.md" || { echo "FAIL: frontend row should be added with iterating"; exit 1; }

# Case H: user-set status (e.g. 'blocked') is NOT overwritten on re-entry
python3 - "docs/super-manus/roadmap.md" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = re.sub(r"^\| api \| iterating \|", "| api | blocked |", text, count=1, flags=re.MULTILINE)
p.write_text(text)
PY
sm_update "api" "fix-bug" >/dev/null
grep -qE "^\| api \| blocked \|" "docs/super-manus/roadmap.md" || { echo "FAIL: blocked status should be preserved (only not-started flips automatically), got:"; cat "docs/super-manus/roadmap.md"; exit 1; }

# Case I: user-set Note column preserved
python3 - "docs/super-manus/roadmap.md" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = re.sub(r"^\| frontend \| iterating \|\s*\|", "| frontend | iterating | owner: alice |", text, count=1, flags=re.MULTILINE)
p.write_text(text)
PY
sm_update "frontend" "second-update" >/dev/null
grep -qF "owner: alice" "docs/super-manus/roadmap.md" || { echo "FAIL: user-set Note should be preserved after second sm-update, got:"; cat "docs/super-manus/roadmap.md"; exit 1; }

# v0.8.1: per-agent model override section in sync.md.
grep -qiE "## Per-agent model override|Per-agent model override \(v0\.8" "$F" \
  || { echo "FAIL: v0.8.1 must declare a Per-agent model override section in commands/sync.md"; exit 1; }
grep -qF "sm_agent_model" "$F" \
  || { echo "FAIL: v0.8.1 must invoke sm_agent_model helper for model resolution"; exit 1; }

echo OK
