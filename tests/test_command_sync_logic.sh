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

# Case A: /sync command markdown exists and has v0.2 contract markers
F="$REPO_ROOT/commands/sync.md"
[ -f "$F" ] || { echo "FAIL: commands/sync.md missing"; exit 1; }
grep -qF ".super-manus/active" "$F" || { echo "FAIL: sync.md must read .super-manus/active"; exit 1; }
grep -qF "scripts/sm-update.sh" "$F" || { echo "FAIL: sync.md must invoke scripts/sm-update.sh"; exit 1; }
grep -qF "prd/<module>.md" "$F" || { echo "FAIL: sync.md must reference per-module PRD"; exit 1; }
grep -qiF "drift" "$F" || { echo "FAIL: sync.md must mention drift detection"; exit 1; }

# Drift check uses the using-sm Drift check protocol (LSP + grep cooperation, not pure text)
grep -qF "Drift check protocol" "$F" || { echo "FAIL: sync.md must reference using-sm's Drift check protocol"; exit 1; }
grep -qF "LSP" "$F" || { echo "FAIL: sync.md drift check must invoke LSP, not just text scan"; exit 1; }
grep -qiE "double-source|cross-check|both LSP and" "$F" || { echo "FAIL: sync.md must keep the double-source rule visible"; exit 1; }

# Case B: invalid args
if sm_update 2>/dev/null; then echo "FAIL: missing args should be rejected"; exit 1; fi
if sm_update "api" 2>/dev/null; then echo "FAIL: single arg should be rejected"; exit 1; fi
if sm_update "API" "mvp" 2>/dev/null; then echo "FAIL: uppercase module should be rejected"; exit 1; fi
if sm_update "api" "MVP" 2>/dev/null; then echo "FAIL: uppercase update name should be rejected"; exit 1; fi
if sm_update "-leading" "mvp" 2>/dev/null; then echo "FAIL: leading hyphen module should be rejected"; exit 1; fi

# Case C: no active feature → exit non-zero
mkdir -p .super-manus
if sm_update "api" "mvp" 2>/dev/null; then echo "FAIL: missing .super-manus/active should be rejected"; exit 1; fi

# Case D: active feature exists but is v0.1 layout (no prd/ folder) → exit non-zero
echo "2026-04-01-legacy" > .super-manus/active
mkdir -p docs/super-manus/2026-04-01-legacy
touch docs/super-manus/2026-04-01-legacy/prd.md
if sm_update "api" "mvp" 2>/dev/null; then echo "FAIL: v0.1 feature should be rejected by sm-update"; exit 1; fi
rm -rf docs/super-manus .super-manus/active
mkdir -p .super-manus

# Case E: happy path — start v0.2 feature, run sm-update for module 'api' with name 'mvp'
sm_start "demo" >/dev/null
TODAY=$(date +%F)
FEATURE="docs/super-manus/${TODAY}-demo"
out=$(sm_update "api" "mvp")
UPDATE="$FEATURE/impl/api/${TODAY}-mvp"
[ -d "$UPDATE" ] || { echo "FAIL: update folder not created at $UPDATE"; exit 1; }
[ -f "$UPDATE/task_plan.md" ] || { echo "FAIL: task_plan.md not seeded"; exit 1; }
[ -f "$UPDATE/findings.md" ] || { echo "FAIL: findings.md not seeded"; exit 1; }
[ -f "$UPDATE/progress.md" ] || { echo "FAIL: progress.md not seeded"; exit 1; }
[ -d "$UPDATE/tasks" ] || { echo "FAIL: tasks/ subfolder not created"; exit 1; }

# task_plan.md must rewrite prd.md → relative path to per-module PRD
grep -qF "../../../prd/api.md" "$UPDATE/task_plan.md" || { echo "FAIL: task_plan.md should point at ../../../prd/api.md, got:"; cat "$UPDATE/task_plan.md"; exit 1; }
grep -qF "prd.md" "$UPDATE/task_plan.md" && grep -v "../../../prd/api.md" "$UPDATE/task_plan.md" | grep -qF "(prd.md)" && { echo "FAIL: task_plan.md still has bare prd.md ref"; exit 1; } || true

# Roadmap should now have an api row with status=iterating
grep -qE "^\| api \| iterating \|" "$FEATURE/roadmap.md" || { echo "FAIL: roadmap.md should have api row with iterating status, got:"; cat "$FEATURE/roadmap.md"; exit 1; }
# Placeholder <module-a> row should be gone
grep -qF "<module-a>" "$FEATURE/roadmap.md" && { echo "FAIL: roadmap placeholder <module-a> row should have been dropped after first sm-update"; exit 1; } || true

# Echoed path should be the new update folder
echo "$out" | grep -q "$UPDATE" || { echo "FAIL: echo path should match update folder, got: $out"; exit 1; }

# Case F: re-running with same args → exit non-zero (folder exists)
if sm_update "api" "mvp" 2>/dev/null; then echo "FAIL: duplicate update should be rejected"; exit 1; fi

# Case G: second module gets its own row appended; first module's iterating status preserved
sm_update "frontend" "mvp" >/dev/null
grep -qE "^\| api \| iterating \|" "$FEATURE/roadmap.md" || { echo "FAIL: api row should still be iterating after frontend sm-update"; exit 1; }
grep -qE "^\| frontend \| iterating \|" "$FEATURE/roadmap.md" || { echo "FAIL: frontend row should be added with iterating"; exit 1; }

# Case H: user-set status (e.g. 'blocked') is NOT overwritten on re-entry
# Pre-set api to blocked then run a NEW update for api — status should stay blocked
python3 - "$FEATURE/roadmap.md" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = re.sub(r"^\| api \| iterating \|", "| api | blocked |", text, count=1, flags=re.MULTILINE)
p.write_text(text)
PY
sm_update "api" "fix-bug" >/dev/null
grep -qE "^\| api \| blocked \|" "$FEATURE/roadmap.md" || { echo "FAIL: blocked status should be preserved (only not-started flips automatically), got:"; cat "$FEATURE/roadmap.md"; exit 1; }

# Case I: user-set Note column preserved
python3 - "$FEATURE/roadmap.md" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
text = p.read_text()
text = re.sub(r"^\| frontend \| iterating \|\s*\|", "| frontend | iterating | owner: alice |", text, count=1, flags=re.MULTILINE)
p.write_text(text)
PY
sm_update "frontend" "second-update" >/dev/null
grep -qF "owner: alice" "$FEATURE/roadmap.md" || { echo "FAIL: user-set Note should be preserved after second sm-update, got:"; cat "$FEATURE/roadmap.md"; exit 1; }

echo OK
